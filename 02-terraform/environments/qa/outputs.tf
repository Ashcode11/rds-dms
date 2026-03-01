# ============================================================
# OUTPUTS: QA Environment
# ============================================================

output "qa_rds_endpoint" {
  description = "QA RDS SQL Server endpoint (host:port)"
  value       = module.rds_qa.db_instance_endpoint
}

output "qa_rds_id" {
  description = "QA RDS instance identifier"
  value       = module.rds_qa.db_instance_id
}

output "qa_rds_arn" {
  description = "QA RDS instance ARN"
  value       = module.rds_qa.db_instance_arn
}
