# ==============================================================================
# Module: Application & Compute Tier (Multi-AZ)
# ==============================================================================

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "production"
}

variable "instance_type" {
  type        = string
  description = "EC2 worker instance class"
  default     = "t3.large"
}

# 1. Customer assets storage vault
resource "aws_s3_bucket" "app_vault" {
  bucket = "acme-${var.environment}-customer-vault-us-east-1"
}

# 2. ALB Access and audit logs
resource "aws_s3_bucket" "alb_logs" {
  bucket = "acme-${var.environment}-alb-waf-access-logs"
}

# 3. Multi-AZ compute nodes
resource "aws_instance" "app_worker_az1" {
  instance_type = var.instance_type
  tags = {
    Name             = "acme-${var.environment}-api-worker-01"
    Environment      = var.environment
    Tier             = "Application-Tier"
    AvailabilityZone = "us-east-1a"
    Role             = "payment-processing"
    Compliance       = "PCI-DSS-Level-1"
  }
}

resource "aws_instance" "app_worker_az2" {
  instance_type = var.instance_type
  tags = {
    Name             = "acme-${var.environment}-api-worker-02"
    Environment      = var.environment
    Tier             = "Application-Tier"
    AvailabilityZone = "us-east-1b"
    Role             = "payment-processing"
    Compliance       = "PCI-DSS-Level-1"
  }
}

# 4. Central application log group
resource "aws_cloudwatch_log_group" "api_logs" {
  name = "/aws/acme/${var.environment}/api-gateway"
}

output "vault_bucket" {
  value = aws_s3_bucket.app_vault.bucket
}

output "worker_ids" {
  value = [aws_instance.app_worker_az1.id, aws_instance.app_worker_az2.id]
}
