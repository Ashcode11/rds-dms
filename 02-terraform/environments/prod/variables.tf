variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "<AWS_PRIMARY_REGION>"   # e.g. "us-west-1"
}

variable "dr_region" {
  description = "DR AWS region"
  type        = string
  default     = "<AWS_DR_REGION>"        # e.g. "us-east-1"
}

variable "db_password" {
  description = "Master DB password — pass via env var TF_VAR_db_password"
  type        = string
  sensitive   = true
}

variable "source_password" {
  description = "Source EC2 SQL Server password — pass via env var TF_VAR_source_password"
  type        = string
  sensitive   = true
}
