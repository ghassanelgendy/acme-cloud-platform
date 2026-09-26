output "vpc_id" {
  description = "Production VPC identifier"
  value       = module.vpc.vpc_id
}

output "load_balancer_arn" {
  description = "Production application load balancer ARN"
  value       = module.app_tier.alb_arn
}

output "customer_vault_bucket" {
  description = "Production Customer Vault S3 Bucket"
  value       = module.app_tier.vault_bucket
}

output "database_cluster_identifier" {
  description = "Core PostgreSQL RDS Database Identifier"
  value       = module.db_tier.db_identifier
}

output "database_replica_identifier" {
  description = "Core PostgreSQL read replica identifier"
  value       = module.db_tier.replica_identifier
}

output "api_workers" {
  description = "Application tier EC2 worker node IDs"
  value       = module.app_tier.worker_ids
}

output "worker_autoscaling_group" {
  description = "Payment worker AutoScaling group name"
  value       = module.app_tier.asg_name
}

output "payment_ingest_queue" {
  description = "SQS payment ingest queue URL"
  value       = module.app_tier.ingest_queue_url
}

output "redis_cache_cluster" {
  description = "ElastiCache Redis cluster id"
  value       = module.db_tier.cache_cluster_id
}

output "transactions_ledger_table" {
  description = "DynamoDB transactions ledger table"
  value       = module.db_tier.ledger_table
}

output "sre_agent_role_arn" {
  description = "Zero-trust SRE agent execution role ARN"
  value       = module.security_tier.agent_role_arn
}

output "security_audit_bucket" {
  description = "Security audit archive bucket"
  value       = module.security_tier.audit_bucket
}

output "analytics_warehouse_identifier" {
  description = "Analytics warehouse RDS identifier"
  value       = module.db_tier.analytics_db_identifier
}

output "billing_database_identifier" {
  description = "Billing PostgreSQL RDS identifier"
  value       = module.db_tier.billing_db_identifier
}

output "audit_events_table" {
  description = "Audit events DynamoDB table"
  value       = module.db_tier.audit_events_table
}

output "notification_fanout_queue" {
  description = "Notification fan-out SQS queue URL"
  value       = module.app_tier.notification_fanout_queue
}

output "audit_events_queue" {
  description = "Security audit events SQS queue URL"
  value       = module.app_tier.audit_events_queue
}

output "payment_event_topic_arn" {
  description = "Payment events SNS topic ARN"
  value       = module.app_tier.payment_event_topic_arn
}

output "security_incident_topic_arn" {
  description = "Security incidents SNS topic ARN"
  value       = module.app_tier.security_incident_topic_arn
}

output "data_lake_buckets" {
  description = "Data lake & analytics buckets"
  value = [
    module.app_tier.vault_bucket,
    "acme-production-data-ingress-raw",
    "acme-production-data-export-ready",
    "acme-production-ml-artifact-store",
  ]
}