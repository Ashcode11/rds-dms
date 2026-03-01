# ============================================================
# OUTPUTS: DR Environment
# ============================================================

output "dr_rds_endpoint" {
  description = "DR warm standby RDS endpoint — activate during DR event"
  value       = aws_db_instance.dr_standby.endpoint
}

output "dr_rds_id" {
  description = "DR RDS instance identifier"
  value       = aws_db_instance.dr_standby.id
}

output "dr_rds_arn" {
  description = "DR RDS instance ARN"
  value       = aws_db_instance.dr_standby.arn
}

output "dr_backup_vault_arn" {
  description = "DR Backup vault ARN (receives cross-region copies from prod)"
  value       = aws_backup_vault.dr_vault.arn
}

output "dr_backup_replication_id" {
  description = "Automated backup replication resource ID"
  value       = aws_db_instance_automated_backups_replication.prod_to_dr.id
}
