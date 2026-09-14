# ==============================================================================
# Module: Networking & VPC Tier
# ==============================================================================

variable "environment" {
  type        = string
  description = "Environment name (e.g. prod, staging)"
  default     = "production"
}

# Audit & WAF log storage bucket for VPC flow logs
resource "aws_s3_bucket" "vpc_flow_logs" {
  bucket = "acme-${var.environment}-vpc-flow-logs"
}

resource "aws_cloudwatch_log_group" "vpc_flow_log_group" {
  name = "/aws/acme/${var.environment}/vpc-flow-logs"
}

output "flow_log_bucket" {
  value = aws_s3_bucket.vpc_flow_logs.bucket
}
