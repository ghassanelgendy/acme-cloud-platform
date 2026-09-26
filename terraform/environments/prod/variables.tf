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

variable "vpc_cidr" {
  description = "CIDR block for the production VPC"
  type        = string
  default     = "10.0.0.0/16"
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

variable "db_allocated_storage" {
  description = "Allocated storage (GB) for the core PostgreSQL cluster"
  type        = string
  default     = "500"
}

variable "asg_min_size" {
  description = "Minimum worker fleet size"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum worker fleet size"
  type        = number
  default     = 6
}