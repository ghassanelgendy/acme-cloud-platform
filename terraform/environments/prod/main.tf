# ==============================================================================
# Acme Corporation - Production Cloud Infrastructure
# Environment: Production (us-east-1)
# High-Availability 2-Tier Architecture (Modularized)
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Organization = "Acme Corp"
      Environment  = "production"
      ManagedBy    = "Terraform"
      Project      = "Core-Banking-Platform"
      Owner        = "CloudPlatform-Team"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. VPC & AUDIT LOGGING MODULE
# ------------------------------------------------------------------------------

module "vpc" {
  source      = "../../modules/vpc"
  environment = var.environment
}

# ------------------------------------------------------------------------------
# 2. APPLICATION & COMPUTE TIER (Multi-AZ Worker Fleet)
# ------------------------------------------------------------------------------

module "app_tier" {
  source        = "../../modules/app-tier"
  environment   = var.environment
  instance_type = var.app_instance_type
}

# ------------------------------------------------------------------------------
# 3. DATABASE & COMPLIANCE TIER (Multi-AZ PostgreSQL & Secrets)
# ------------------------------------------------------------------------------

module "db_tier" {
  source            = "../../modules/db-tier"
  environment       = var.environment
  db_instance_class = var.db_instance_class
}
