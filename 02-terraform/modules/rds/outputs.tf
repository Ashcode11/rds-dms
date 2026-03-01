# ============================================================
# MODULE OUTPUTS: rds
# ============================================================

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.this.arn
}

output "db_endpoint" {
  description = "RDS instance endpoint (host:port)"
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "RDS instance hostname"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS instance port"
  value       = aws_db_instance.this.port
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.this.name
}

output "option_group_name" {
  description = "RDS option group name"
  value       = aws_db_option_group.this.name
}

output "parameter_group_name" {
  description = "RDS parameter group name"
  value       = aws_db_parameter_group.this.name
}
