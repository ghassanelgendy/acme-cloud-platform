# ==============================================================================
# Module: Security & Compliance Tier
# KMS encryption keys, zero-trust IAM roles with a hard permissions boundary
# for the autonomous agent, and the security audit log archive.
# ==============================================================================

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "production"
}

# 1. KMS customer-managed keys
resource "aws_kms_key" "vault_key" {
  description             = "Acme customer vault KMS key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags = {
    Name        = "acme-${var.environment}-vault-key"
    Environment = var.environment
  }
}

resource "aws_kms_key" "database_key" {
  description             = "Acme database encryption KMS key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags = {
    Name        = "acme-${var.environment}-database-key"
    Environment = var.environment
  }
}

resource "aws_kms_key" "app_key" {
  description             = "Acme application signing KMS key"
  deletion_window_in_days = 30
  tags = {
    Name        = "acme-${var.environment}-app-key"
    Environment = var.environment
  }
}

# 1b. Service-scoped keys (S3, RDS, SQS, SNS, logs, signing, backup)
resource "aws_kms_key" "s3_data_key" {
  description             = "Acme S3 data-at-rest encryption key"
  deletion_window_in_days = 30
  tags = {
    Name        = "acme-${var.environment}-s3-key"
    Environment = var.environment
  }
}

resource "aws_kms_key" "rds_key" {
  description             = "Acme RDS encryption key"
  deletion_window_in_days = 30
  tags = {
    Name        = "acme-${var.environment}-rds-key"
    Environment = var.environment
  }
}

resource "aws_kms_key" "sqs_key" {
  description             = "Acme SQS encryption key"
  deletion_window_in_days = 30
  tags = {
    Name        = "acme-${var.environment}-sqs-key"
    Environment = var.environment
  }
}

resource "aws_kms_key" "sns_key" {
  description             = "Acme SNS encryption key"
  deletion_window_in_days = 30
  tags = {
    Name        = "acme-${var.environment}-sns-key"
    Environment = var.environment
  }
}

resource "aws_kms_key" "log_key" {
  description             = "Acme CloudWatch logs encryption key"
  deletion_window_in_days = 30
  tags = {
    Name        = "acme-${var.environment}-log-key"
    Environment = var.environment
  }
}

resource "aws_kms_key" "code_signing_key" {
  description             = "Acme deployment code-signing key"
  deletion_window_in_days = 30
  tags = {
    Name        = "acme-${var.environment}-code-signing-key"
    Environment = var.environment
  }
}

resource "aws_kms_key" "backup_key" {
  description             = "Acme backup archive encryption key"
  deletion_window_in_days = 30
  tags = {
    Name        = "acme-${var.environment}-backup-key"
    Environment = var.environment
  }
}

# 2. Zero-trust IAM: scoped agent run role with an immutable permissions boundary
resource "aws_iam_policy" "sre_mission_policy" {
  name        = "acme-${var.environment}-sre-mission-policy"
  description = "Least-privilege read + health-check mission for the SRE agent"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets", "s3:ListBucket", "s3:GetBucketTagging", "s3:GetBucketVersioning"]
        Resource = ["arn:aws:s3:::*"]
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeTags", "ec2:DescribeAutoScalingGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["rds:DescribeDBInstances", "rds:DescribeDBSnapshots", "rds:DescribeDBClusters"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:ListSecrets", "secretsmanager:DescribeSecret"]
        Resource = "*"
      },
      {
        Effect   = "Deny"
        Action   = ["rds:DeleteDBInstance", "ec2:TerminateInstances", "dynamodb:DeleteTable", "elasticache:DeleteCacheCluster"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "sre_agent_role" {
  name = "acme-${var.environment}-sre-agent-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  permissions_boundary = aws_iam_policy.sre_mission_policy.arn
  tags = {
    Name        = "acme-${var.environment}-sre-agent-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "sre_mission" {
  role       = aws_iam_role.sre_agent_role.name
  policy_arn = aws_iam_policy.sre_mission_policy.arn
}

resource "aws_iam_instance_profile" "sre_agent_profile" {
  name = "acme-${var.environment}-sre-agent-profile"
  role = aws_iam_role.sre_agent_role.name
}

# 2b. Operations roles (analytics, warehouse, backup, monitoring, deploy, batch)
resource "aws_iam_role" "analytics_role" {
  name = "acme-${var.environment}-analytics-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = {
    Name        = "acme-${var.environment}-analytics-role"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "analytics_read_policy" {
  name        = "acme-${var.environment}-analytics-read-policy"
  description = "Read access over analytics warehouse and data lake"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds:DescribeDBInstances", "rds:DescribeDBSnapshots"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::acme-${var.environment}-data-export-ready", "arn:aws:s3:::acme-${var.environment}-data-export-ready/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "analytics_attach" {
  role       = aws_iam_role.analytics_role.name
  policy_arn = aws_iam_policy.analytics_read_policy.arn
}

resource "aws_iam_role" "backup_operator" {
  name = "acme-${var.environment}-backup-operator"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })
  tags = {
    Name        = "acme-${var.environment}-backup-operator"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "backup_service_policy" {
  name        = "acme-${var.environment}-backup-service-policy"
  description = "Backup vault access and snapshot lifecycle"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds:CreateDBSnapshot", "rds:DescribeDBSnapshots", "s3:PutObject"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backup_attach" {
  role       = aws_iam_role.backup_operator.name
  policy_arn = aws_iam_policy.backup_service_policy.arn
}

resource "aws_iam_role" "monitoring_role" {
  name = "acme-${var.environment}-monitoring-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = {
    Name        = "acme-${var.environment}-monitoring-role"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "monitoring_policy" {
  name        = "acme-${var.environment}-monitoring-policy"
  description = "Read telemetry and write metrics"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricData", "logs:DescribeLogGroups", "logs:GetLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "monitoring_attach" {
  role       = aws_iam_role.monitoring_role.name
  policy_arn = aws_iam_policy.monitoring_policy.arn
}

resource "aws_iam_role" "deployer_role" {
  name = "acme-${var.environment}-deployer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
    }]
  })
  tags = {
    Name        = "acme-${var.environment}-deployer-role"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "deploy_policy" {
  name        = "acme-${var.environment}-deploy-policy"
  description = "Limit deploy role to launch-template updates and SNS notify"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateLaunchTemplateVersion", "autoscaling:UpdateAutoScalingGroup", "sns:Publish"]
        Resource = "*"
      },
      {
        Effect   = "Deny"
        Action   = ["rds:DeleteDBInstance", "s3:DeleteBucket", "dynamodb:DeleteTable"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "deployer_attach" {
  role       = aws_iam_role.deployer_role.name
  policy_arn = aws_iam_policy.deploy_policy.arn
}

resource "aws_iam_role" "batch_role" {
  name = "acme-${var.environment}-batch-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = {
    Name        = "acme-${var.environment}-batch-role"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "batch_policy" {
  name        = "acme-${var.environment}-batch-policy"
  description = "Batch processing queue + log access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "batch_attach" {
  role       = aws_iam_role.batch_role.name
  policy_arn = aws_iam_policy.batch_policy.arn
}

# 3. Security audit log archive
resource "aws_cloudwatch_log_group" "security_audit_group" {
  name              = "/aws/acme/${var.environment}/security/audit"
  retention_in_days = 365
}

resource "aws_s3_bucket" "security_audit_bucket" {
  bucket = "acme-${var.environment}-security-audit-archive"
}

resource "aws_s3_bucket" "security_events_bucket" {
  bucket = "acme-${var.environment}-security-events-archive"
}

# 4. Security configuration & baseline parameters (SSM)
resource "aws_ssm_parameter" "security_baseline" {
  name  = "/acme/${var.environment}/security/config-baseline"
  type  = "String"
  value = "guardduty=on;iam_access_analyzer=on;config_recorder=us-east-1;s3_block_public=on"
}

resource "aws_ssm_parameter" "findings_export_destination" {
  name  = "/acme/${var.environment}/security/findings-export"
  type  = "String"
  value = "s3://acme-${var.environment}-security-events-archive/findings/"
}

resource "aws_ssm_parameter" "incident_response_runbook" {
  name  = "/acme/${var.environment}/security/incident-runbook"
  type  = "String"
  value = "page:security-oncall;severity:critical;timeout:15m;escalate:cloud-platform"
}

output "agent_role_arn" {
  value = aws_iam_role.sre_agent_role.arn
}

output "vault_key_arn" {
  value = aws_kms_key.vault_key.arn
}

output "audit_bucket" {
  value = aws_s3_bucket.security_audit_bucket.bucket
}

output "security_events_bucket" {
  value = aws_s3_bucket.security_events_bucket.bucket
}

output "batch_role_name" {
  value = aws_iam_role.batch_role.name
}

output "deployer_role_name" {
  value = aws_iam_role.deployer_role.name
}