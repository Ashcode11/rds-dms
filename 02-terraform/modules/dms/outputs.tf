# ============================================================
# MODULE OUTPUTS: dms
# ============================================================

output "replication_instance_arn" {
  description = "DMS replication instance ARN"
  value       = aws_dms_replication_instance.this.replication_instance_arn
}

output "replication_instance_id" {
  description = "DMS replication instance ID"
  value       = aws_dms_replication_instance.this.replication_instance_id
}

output "source_endpoint_arn" {
  description = "DMS source endpoint ARN"
  value       = aws_dms_endpoint.source.endpoint_arn
}

output "target_endpoint_arn" {
  description = "DMS target endpoint ARN"
  value       = aws_dms_endpoint.target.endpoint_arn
}

output "replication_task_arn" {
  description = "DMS replication task ARN"
  value       = aws_dms_replication_task.this.replication_task_arn
}
