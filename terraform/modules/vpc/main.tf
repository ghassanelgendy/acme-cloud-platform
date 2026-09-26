# ==============================================================================
# Module: Networking & VPC Tier
# Production-grade three-tier networking: VPC, 3-AZ subnets, NAT, NACLs, VPC
# flow logs, and per-tier security groups.
# ==============================================================================

variable "environment" {
  type        = string
  description = "Environment name (e.g. prod, staging)"
  default     = "production"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the Acme VPC"
  default     = "10.0.0.0/16"
}

# --- Availability zones (us-east-1) -----------------------------------------

locals {
  azs = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# 1. VPC + core networking
resource "aws_vpc" "acme_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name        = "acme-${var.environment}-vpc"
    Environment = var.environment
    Tier        = "Networking-Tier"
    GuardDuty   = "enabled"
  }
}

resource "aws_internet_gateway" "acme_igw" {
  vpc_id = aws_vpc.acme_vpc.id
  tags = {
    Name = "acme-${var.environment}-igw"
  }
}

# 2. 3-AZ public subnets (ALB, NAT, leapfrog)
resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.acme_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.acme_vpc.cidr_block, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name       = "acme-${var.environment}-public-${local.azs[count.index]}"
    Tier       = "public"
    Kubernetes = "shared"
  }
}

# 3. 3-AZ private subnets (compute + data plane)
resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.acme_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.acme_vpc.cidr_block, 8, 10 + count.index)
  availability_zone = local.azs[count.index]
  tags = {
    Name       = "acme-${var.environment}-private-${local.azs[count.index]}"
    Tier       = "private"
    Kubernetes = "shared"
  }
}

# 4. NAT gateway in AZ-a for private egress
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
    Name = "acme-${var.environment}-nat-eip"
  }
}

resource "aws_nat_gateway" "acme_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[0].id
  tags = {
    Name = "acme-${var.environment}-nat"
  }
}

# 5. Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.acme_vpc.id
  tags = {
    Name = "acme-${var.environment}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.acme_igw.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.acme_vpc.id
  tags = {
    Name = "acme-${var.environment}-private-rt"
  }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.acme_nat.id
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# 6. Network ACLs (explicit deny on known attack ports for public subnets)
resource "aws_network_acl" "public_nacl" {
  vpc_id     = aws_vpc.acme_vpc.id
  subnet_ids = aws_subnet.public[*].id
  tags = {
    Name = "acme-${var.environment}-public-nacl"
  }
}

resource "aws_network_acl_rule" "public_allow_http" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "public_allow_https" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "public_deny_rdp" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
  from_port      = 3389
  to_port        = 3389
}

resource "aws_network_acl_rule" "public_deny_ssh" {
  network_acl_id = aws_network_acl.public_nacl.id
  rule_number    = 210
  egress         = false
  protocol       = "tcp"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
  from_port      = 22
  to_port        = 22
}

# 7. VPC Flow Logs → S3 + CloudWatch
resource "aws_s3_bucket" "vpc_flow_logs" {
  bucket = "acme-${var.environment}-vpc-flow-logs"
}

resource "aws_cloudwatch_log_group" "vpc_flow_log_group" {
  name = "/aws/acme/${var.environment}/vpc-flow-logs"
}

resource "aws_flow_log" "acme_flow_log" {
  log_destination      = aws_s3_bucket.vpc_flow_logs.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.acme_vpc.id
  tags = {
    Name = "acme-${var.environment}-flow-log"
  }
}

# 8. Security groups: API/ALB, application workers, database, cache, VPC endpoints
resource "aws_security_group" "alb_sg" {
  name        = "acme-${var.environment}-alb-sg"
  description = "Allows HTTP/S ingress to the ALB"
  vpc_id      = aws_vpc.acme_vpc.id
}

resource "aws_security_group_rule" "alb_allow_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_sg.id
}

resource "aws_security_group_rule" "alb_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb_sg.id
}

resource "aws_security_group" "app_sg" {
  name        = "acme-${var.environment}-app-sg"
  description = "Application worker fleet security group"
  vpc_id      = aws_vpc.acme_vpc.id
}

resource "aws_security_group_rule" "app_ingress_alb" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  security_group_id        = aws_security_group.app_sg.id
}

resource "aws_security_group" "db_sg" {
  name        = "acme-${var.environment}-db-sg"
  description = "Database tier security group"
  vpc_id      = aws_vpc.acme_vpc.id
}

resource "aws_security_group_rule" "db_ingress_app" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app_sg.id
  security_group_id        = aws_security_group.db_sg.id
}

# Cache tier (Redis) -- only the application fleet may reach it
resource "aws_security_group" "cache_sg" {
  name        = "acme-${var.environment}-cache-sg"
  description = "ElastiCache Redis tier security group"
  vpc_id      = aws_vpc.acme_vpc.id
}

resource "aws_security_group_rule" "cache_ingress_app" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app_sg.id
  security_group_id        = aws_security_group.cache_sg.id
}

# Batch / offline processing fleet
resource "aws_security_group" "batch_sg" {
  name        = "acme-${var.environment}-batch-sg"
  description = "Batch and offline processing fleet security group"
  vpc_id      = aws_vpc.acme_vpc.id
}

resource "aws_security_group_rule" "batch_ingress_app" {
  type                     = "ingress"
  from_port                = 9000
  to_port                  = 9000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app_sg.id
  security_group_id        = aws_security_group.batch_sg.id
}

# Monitoring / metrics collection agents
resource "aws_security_group" "monitoring_sg" {
  name        = "acme-${var.environment}-monitoring-sg"
  description = "Monitoring and metrics agents security group"
  vpc_id      = aws_vpc.acme_vpc.id
}

resource "aws_security_group_rule" "monitoring_ingress_app" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app_sg.id
  security_group_id        = aws_security_group.monitoring_sg.id
}

# Restricted jump-host access (admin / break-glass only)
resource "aws_security_group" "bastion_sg" {
  name        = "acme-${var.environment}-bastion-sg"
  description = "Restricted admin bastion security group"
  vpc_id      = aws_vpc.acme_vpc.id
}

resource "aws_security_group_rule" "bastion_ingress_admin" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/8"]
  security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_security_group_rule" "bastion_egress_ssh" {
  type              = "egress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/8"]
  security_group_id = aws_security_group.bastion_sg.id
}

# Data science / analytics workbench
resource "aws_security_group" "datascience_sg" {
  name        = "acme-${var.environment}-datascience-sg"
  description = "Data science workbench security group"
  vpc_id      = aws_vpc.acme_vpc.id
}

resource "aws_security_group_rule" "datascience_ingress_app" {
  type                     = "ingress"
  from_port                = 8888
  to_port                  = 8888
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app_sg.id
  security_group_id        = aws_security_group.datascience_sg.id
}

output "vpc_id" {
  value = aws_vpc.acme_vpc.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "app_security_group_id" {
  value = aws_security_group.app_sg.id
}

output "db_security_group_id" {
  value = aws_security_group.db_sg.id
}

output "flow_log_bucket" {
  value = aws_s3_bucket.vpc_flow_logs.bucket
}