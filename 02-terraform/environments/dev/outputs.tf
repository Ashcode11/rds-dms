# ============================================================
# OUTPUTS: DEV Environment
# ============================================================

output "dev_rds_endpoint" {
  description = "DEV RDS SQL Server endpoint (host:port)"
  value       = module.rds_dev.db_instance_endpoint
}

output "dev_rds_id" {
  description = "DEV RDS instance identifier"
  value       = module.rds_dev.db_instance_id
}

output "dev_rds_arn" {
  description = "DEV RDS instance ARN"
  value       = module.rds_dev.db_instance_arn
}
