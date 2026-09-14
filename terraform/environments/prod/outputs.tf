output "customer_vault_bucket" {
  description = "Production Customer Vault S3 Bucket"
  value       = module.app_tier.vault_bucket
}

output "database_cluster_identifier" {
  description = "Core PostgreSQL RDS Database Identifier"
  value       = module.db_tier.db_identifier
}

output "api_workers" {
  description = "Application tier EC2 worker node IDs"
  value       = module.app_tier.worker_ids
}
