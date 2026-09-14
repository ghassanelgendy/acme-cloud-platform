# ==============================================================================
# Module: Database & Compliance Tier
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

# 1. Multi-AZ Core PostgreSQL Engine
resource "aws_db_instance" "core_postgres" {
  identifier        = "acme-${var.environment}-core-postgres-cluster"
  engine            = "postgres"
  instance_class    = var.db_instance_class
  allocated_storage = var.allocated_storage
}

# 2. Database Backup & Snapshot Retention Bucket
resource "aws_s3_bucket" "db_backups" {
  bucket = "acme-${var.environment}-db-snapshots-archive"
}

# 3. AWS Secrets Manager Master Credentials Vault
resource "aws_secretsmanager_secret" "db_master_credentials" {
  name        = "acme/${var.environment}/database/core_postgres_master"
  description = "PCI-DSS Compliant PostgreSQL Master Credentials"
  secret_string = "{\"engine\":\"postgres\",\"host\":\"acme-${var.environment}-core-postgres-cluster.internal\",\"port\":5432,\"username\":\"acme_master_admin\"}"
}

output "db_identifier" {
  value = aws_db_instance.core_postgres.identifier
}

output "backup_bucket" {
  value = aws_s3_bucket.db_backups.bucket
}
