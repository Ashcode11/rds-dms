variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "<AWS_REGION>"   # e.g. "us-west-1"
}

variable "db_password" {
  description = "Master DB password — pass via env var TF_VAR_db_password or Secrets Manager"
  type        = string
  sensitive   = true
}

variable "source_password" {
  description = "Source EC2 SQL Server password — pass via env var TF_VAR_source_password"
  type        = string
  sensitive   = true
}
