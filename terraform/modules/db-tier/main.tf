# ==============================================================================
# Module: Database & Data Tier
# Multi-AZ PostgreSQL with encrypted read replica, Redis cache, DynamoDB
# payment ledger, Secrets Manager vault, and versioned backup archive.
# ==============================================================================

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "production"
}

variable "db_instance_class" {
  type        = string
  description = "RDS DB instance class"
  default     = "db.r6g.xlarge"
}

variable "allocated_storage" {
  type        = string
  description = "Allocated storage in GB"
  default     = "500"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets for the data tier"
}

variable "db_security_group_id" {
  type        = string
  description = "Security group attached to database resources"
}

# 1. Multi-AZ Core PostgreSQL (disaster-recovery protected)
resource "aws_db_subnet_group" "db_subnets" {
  name       = "acme-${var.environment}-db-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_parameter_group" "postgres_params" {
  name   = "acme-${var.environment}-postgres-pg"
  family = "postgres15"
}

resource "aws_db_instance" "core_postgres" {
  identifier                = "acme-${var.environment}-core-postgres-cluster"
  engine                    = "postgres"
  engine_version            = "15.4"
  instance_class            = var.db_instance_class
  allocated_storage         = var.allocated_storage
  storage_encrypted         = true
  multi_az                  = true
  db_subnet_group_name      = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids    = [var.db_security_group_id]
  parameter_group_name      = aws_db_parameter_group.postgres_params.name
  backup_retention_period   = 30
  backup_window             = "03:00-04:00"
  maintenance_window        = "sun:04:00-sun:05:00"
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "acme-${var.environment}-core-postgres-final"
  tags = {
    Name             = "acme-${var.environment}-core-postgres-cluster"
    Environment      = var.environment
    Tier             = "Database-Tier"
    Compliance       = "PCI-DSS-Level-1"
    BusinessCritical = "true"
  }
}

# 2. Encrypted read replica for reporting workloads
resource "aws_db_instance" "read_replica" {
  identifier          = "acme-${var.environment}-core-postgres-replica"
  replicate_source_db = aws_db_instance.core_postgres.identifier
  instance_class      = var.db_instance_class
  multi_az            = false
  deletion_protection = true
  skip_final_snapshot = false
}

# 2b. Analytics warehouse & line-of-business databases
resource "aws_db_parameter_group" "analytics_params" {
  name   = "acme-${var.environment}-analytics-pg"
  family = "postgres15"
}

resource "aws_db_instance" "analytics_warehouse" {
  identifier              = "acme-${var.environment}-analytics-warehouse"
  engine                  = "postgres"
  engine_version          = "15.4"
  instance_class          = "db.r6g.large"
  allocated_storage       = "200"
  storage_encrypted       = true
  multi_az                = true
  db_subnet_group_name    = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids  = [var.db_security_group_id]
  parameter_group_name    = aws_db_parameter_group.analytics_params.name
  backup_retention_period = 30
  deletion_protection     = true
  tags = {
    Name        = "acme-${var.environment}-analytics-warehouse"
    Environment = var.environment
    Tier        = "Data-Analytics"
  }
}

resource "aws_db_instance" "analytics_warehouse_replica" {
  identifier          = "acme-${var.environment}-analytics-warehouse-replica"
  replicate_source_db = aws_db_instance.analytics_warehouse.identifier
  instance_class      = "db.r6g.large"
  skip_final_snapshot = false
}

resource "aws_db_instance" "billing_postgres" {
  identifier              = "acme-${var.environment}-billing-postgres"
  engine                  = "postgres"
  engine_version          = "15.4"
  instance_class          = "db.t3.xlarge"
  allocated_storage       = "100"
  storage_encrypted       = true
  multi_az                = false
  db_subnet_group_name    = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids  = [var.db_security_group_id]
  backup_retention_period = 30
  tags = {
    Name        = "acme-${var.environment}-billing-postgres"
    Environment = var.environment
    Tier        = "Billing"
  }
}

resource "aws_db_instance" "support_mysql" {
  identifier             = "acme-${var.environment}-support-mysql"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.large"
  allocated_storage      = "80"
  storage_encrypted      = true
  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids = [var.db_security_group_id]
  tags = {
    Name        = "acme-${var.environment}-support-mysql"
    Environment = var.environment
    Tier        = "Support"
  }
}

# 2c. Declared DB snapshots -- cloned as real backup artifacts in the sandbox
resource "aws_db_snapshot" "core_final" {
  db_instance_identifier = aws_db_instance.core_postgres.id
  db_snapshot_identifier = "acme-${var.environment}-core-postgres-final-2026-09"
}

resource "aws_db_snapshot" "analytics_monthly" {
  db_instance_identifier = aws_db_instance.analytics_warehouse.id
  db_snapshot_identifier = "acme-${var.environment}-analytics-warehouse-2026-09"
}

resource "aws_db_snapshot" "billing_dr" {
  db_instance_identifier = aws_db_instance.billing_postgres.id
  db_snapshot_identifier = "acme-${var.environment}-billing-postgres-dr-2026-09"
}

# 3. Redis cache layer for payment sessions
resource "aws_elasticache_subnet_group" "cache_subnets" {
  name       = "acme-${var.environment}-cache-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_cluster" "session_cache" {
  cluster_id           = "acme-${var.environment}-session-cache"
  engine               = "redis"
  node_type            = "cache.t3.medium"
  num_cache_nodes      = 2
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.cache_subnets.name
  security_group_ids   = [var.db_security_group_id]
  tags = {
    Environment = var.environment
    Service     = "payments"
  }
}

# 4. DynamoDB payment ledger & token store
resource "aws_dynamodb_table" "transactions_ledger" {
  name         = "acme-${var.environment}-transactions-ledger"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "transaction_id"
  range_key    = "created_at"
  attribute {
    name = "transaction_id"
    type = "S"
  }
  attribute {
    name = "created_at"
    type = "S"
  }
  point_in_time_recovery {
    enabled = true
  }
  tags = {
    Environment = var.environment
    Service     = "payments"
  }
}

resource "aws_dynamodb_table" "token_store" {
  name         = "acme-${var.environment}-payment-token-store"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "token_id"
  attribute {
    name = "token_id"
    type = "S"
  }
  tags = {
    Environment = var.environment
    Service     = "payments"
  }
}

# 4b. Platform state tables
resource "aws_dynamodb_table" "session_store" {
  name         = "acme-${var.environment}-session-store"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"
  attribute {
    name = "session_id"
    type = "S"
  }
  tags = {
    Environment = var.environment
    Service     = "identity"
  }
}

resource "aws_dynamodb_table" "feature_flags" {
  name         = "acme-${var.environment}-feature-flags"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "flag_key"
  attribute {
    name = "flag_key"
    type = "S"
  }
  tags = {
    Environment = var.environment
    Service     = "platform"
  }
}

resource "aws_dynamodb_table" "customer_profiles" {
  name         = "acme-${var.environment}-customer-profiles"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "customer_id"
  attribute {
    name = "customer_id"
    type = "S"
  }
  tags = {
    Environment = var.environment
    Service     = "payments"
  }
}

resource "aws_dynamodb_table" "audit_events_ledger" {
  name         = "acme-${var.environment}-audit-events-ledger"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"
  attribute {
    name = "event_id"
    type = "S"
  }
  point_in_time_recovery {
    enabled = true
  }
  tags = {
    Environment = var.environment
    Service     = "security"
  }
}

resource "aws_dynamodb_table" "idempotency_keys" {
  name         = "acme-${var.environment}-idempotency-keys"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "idempotency_key"
  attribute {
    name = "idempotency_key"
    type = "S"
  }
  tags = {
    Environment = var.environment
    Service     = "payments"
  }
}

resource "aws_dynamodb_table" "scheduler_tasks" {
  name         = "acme-${var.environment}-scheduler-tasks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "task_id"
  attribute {
    name = "task_id"
    type = "S"
  }
  tags = {
    Environment = var.environment
    Service     = "platform"
  }
}

# 5. AWS Secrets Manager vault
resource "aws_secretsmanager_secret" "db_master_credentials" {
  name        = "acme/${var.environment}/database/core_postgres_master"
  description = "PCI-DSS Compliant PostgreSQL Master Credentials"
}

resource "aws_secretsmanager_secret_version" "db_master_credentials_version" {
  secret_id     = aws_secretsmanager_secret.db_master_credentials.id
  secret_string = <<-JSON
  {"engine":"postgres","host":"acme-${var.environment}-core-postgres-cluster.internal","port":5432,"username":"acme_master_admin","readreplica":"acme-${var.environment}-core-postgres-replica.internal"}
  JSON
}

resource "aws_secretsmanager_secret" "api_gateway_keys" {
  name        = "acme/${var.environment}/apigateway/keys"
  description = "API Gateway signing keys for payment webhooks"
}

resource "aws_secretsmanager_secret_version" "api_gateway_keys_version" {
  secret_id     = aws_secretsmanager_secret.api_gateway_keys.id
  secret_string = <<-JSON
  {"webhook_signing_key":"whsec_live_acme_signing_key","gateway_api_key":"gwy_live_acme_webhook"}
  JSON
}

resource "aws_secretsmanager_secret" "jwt_signing_key" {
  name        = "acme/${var.environment}/jwt/signing"
  description = "JWT signing key for session tokens"
}

resource "aws_secretsmanager_secret_version" "jwt_signing_key_version" {
  secret_id     = aws_secretsmanager_secret.jwt_signing_key.id
  secret_string = <<-JSON
  {"alg":"RS256","kid":"acme-live-1"}
  JSON
}

# 5b. Line-of-business & vendor credentials (held as JSON, cloned into the sandbox)
resource "aws_secretsmanager_secret" "billing_postgres_master" {
  name = "acme/${var.environment}/database/billing_postgres_master"
}

resource "aws_secretsmanager_secret_version" "billing_postgres_master_version" {
  secret_id     = aws_secretsmanager_secret.billing_postgres_master.id
  secret_string = <<-JSON
  {"engine":"postgres","host":"acme-${var.environment}-billing-postgres.internal","port":5432,"username":"billing_admin","readreplica":false}
  JSON
}

resource "aws_secretsmanager_secret" "support_mysql_master" {
  name = "acme/${var.environment}/database/support_mysql_master"
}

resource "aws_secretsmanager_secret_version" "support_mysql_master_version" {
  secret_id     = aws_secretsmanager_secret.support_mysql_master.id
  secret_string = <<-JSON
  {"engine":"mysql","host":"acme-${var.environment}-support-mysql.internal","port":3306,"username":"support_admin"}
  JSON
}

resource "aws_secretsmanager_secret" "payment_gateway_keys" {
  name        = "acme/${var.environment}/payments/gateway_keys"
  description = "Live payment gateway API credentials"
}

resource "aws_secretsmanager_secret_version" "payment_gateway_keys_version" {
  secret_id     = aws_secretsmanager_secret.payment_gateway_keys.id
  secret_string = <<-JSON
  {"publishable_key":"pk_live_51AcME","secret_key":"sk_live_4ca1fe-d0d0-4cafe","webhook_secret":"whsec_live_acme_2026"}
  JSON
}

resource "aws_secretsmanager_secret" "vendor_integrations" {
  name        = "acme/${var.environment}/integrations/vendor_api"
  description = "Vendor integration credentials (fraud & KYC providers)"
}

resource "aws_secretsmanager_secret_version" "vendor_integrations_version" {
  secret_id     = aws_secretsmanager_secret.vendor_integrations.id
  secret_string = <<-JSON
  {"fraud_screener":"frsc_live_ert45f7","kyc_provider":"kyc_live_alpha9","hsm_partner":"hsm_rtx_8890"}
  JSON
}

resource "aws_secretsmanager_secret" "redis_cache_auth" {
  name = "acme/${var.environment}/redis/cache_auth"
}

resource "aws_secretsmanager_secret_version" "redis_cache_auth_version" {
  secret_id     = aws_secretsmanager_secret.redis_cache_auth.id
  secret_string = <<-JSON
  {"engine":"redis","host":"acme-${var.environment}-session-cache.internal","port":6379,"auth":"REDIS_AUTH_7ab1c2"}
  JSON
}

resource "aws_secretsmanager_secret" "smtp_credentials" {
  name = "acme/${var.environment}/notifications/smtp"
}

resource "aws_secretsmanager_secret_version" "smtp_credentials_version" {
  secret_id     = aws_secretsmanager_secret.smtp_credentials.id
  secret_string = <<-JSON
  {"host":"smtp.acme-corp.io","port":587,"username":"no-reply@acme-corp.io","password":"SMTP_LIVE_a1b2c3"}
  JSON
}

resource "aws_secretsmanager_secret" "oauth_client_credentials" {
  name = "acme/${var.environment}/identity/oauth_client"
}

resource "aws_secretsmanager_secret_version" "oauth_client_credentials_version" {
  secret_id     = aws_secretsmanager_secret.oauth_client_credentials.id
  secret_string = <<-JSON
  {"client_id":"acme-platform","client_secret":"OAUTH_CLIENT_9f0e8d","grant_type":"client_credentials"}
  JSON
}

# 6. DB backup & snapshot archive (versioned, tiered to Glacier)
resource "aws_s3_bucket" "db_backups" {
  bucket = "acme-${var.environment}-db-snapshots-archive"
}

resource "aws_s3_bucket_versioning" "backup_versioning" {
  bucket = aws_s3_bucket.db_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup_lifecycle" {
  bucket = aws_s3_bucket.db_backups.id
  rule {
    id     = "tier-to-glacier"
    status = "Enabled"
    filter {
      prefix = ""
    }
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
    expiration {
      days = 365
    }
  }
}

output "db_identifier" {
  value = aws_db_instance.core_postgres.identifier
}

output "replica_identifier" {
  value = aws_db_instance.read_replica.identifier
}

output "backup_bucket" {
  value = aws_s3_bucket.db_backups.bucket
}

output "cache_cluster_id" {
  value = aws_elasticache_cluster.session_cache.cluster_id
}

output "ledger_table" {
  value = aws_dynamodb_table.transactions_ledger.name
}

output "analytics_db_identifier" {
  value = aws_db_instance.analytics_warehouse.identifier
}

output "billing_db_identifier" {
  value = aws_db_instance.billing_postgres.identifier
}

output "audit_events_table" {
  value = aws_dynamodb_table.audit_events_ledger.name
}