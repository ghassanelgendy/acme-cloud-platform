# ==============================================================================
# Acme Corporation - Production Cloud Infrastructure
# Environment: Production (us-east-1)
# High-Availability 4-Tier Architecture (Modularized): Networking / App / Data / Security
# Genuinely production-scale: serverless edge, data lake + analytics, eventing,
# service-scoped encryption, zero-trust operations roles.
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
# TIER 1 - NETWORKING & SECURITY (VPC, subnets, NAT, NACLs, flow logs)
# ------------------------------------------------------------------------------

module "vpc" {
  source      = "../../modules/vpc"
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
}

# ------------------------------------------------------------------------------
# TIER 2 - APPLICATION & EDGE (ALB, worker fleet, vaults, SQS, Lambda, API GW)
# ------------------------------------------------------------------------------

module "app_tier" {
  source                = "../../modules/app-tier"
  environment           = var.environment
  instance_type         = var.app_instance_type
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  private_subnet_ids    = module.vpc.private_subnet_ids
  app_security_group_id = module.vpc.app_security_group_id
}

# ------------------------------------------------------------------------------
# TIER 3 - DATABASE & DATA (PostgreSQL + replica, Redis, DynamoDB, Secrets, backups)
# ------------------------------------------------------------------------------

module "db_tier" {
  source               = "../../modules/db-tier"
  environment          = var.environment
  db_instance_class    = var.db_instance_class
  private_subnet_ids   = module.vpc.private_subnet_ids
  db_security_group_id = module.vpc.db_security_group_id
}

# ------------------------------------------------------------------------------
# TIER 4 - SECURITY & COMPLIANCE (KMS, zero-trust IAM boundary, audit archive)
# ------------------------------------------------------------------------------

module "security_tier" {
  source      = "../../modules/security-tier"
  environment = var.environment
}