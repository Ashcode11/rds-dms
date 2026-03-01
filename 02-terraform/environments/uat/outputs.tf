# ============================================================
# OUTPUTS: UAT Environment
# ============================================================

output "uat_rds_endpoint" {
  description = "UAT RDS SQL Server endpoint (host:port)"
  value       = module.rds_uat.db_instance_endpoint
}

output "uat_rds_id" {
  description = "UAT RDS instance identifier"
  value       = module.rds_uat.db_instance_id
}

output "uat_rds_arn" {
  description = "UAT RDS instance ARN"
  value       = module.rds_uat.db_instance_arn
}

output "uat_dms_replication_instance_arn" {
  description = "UAT DMS replication instance ARN"
  value       = module.dms_uat.replication_instance_arn
}
