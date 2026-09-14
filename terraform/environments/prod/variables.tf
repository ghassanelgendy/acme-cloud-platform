variable "aws_region" {
  description = "AWS region for production infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "db_instance_class" {
  description = "RDS DB instance class"
  type        = string
  default     = "db.r6g.xlarge"
}

variable "app_instance_type" {
  description = "EC2 instance type for application workers"
  type        = string
  default     = "t3.large"
}
