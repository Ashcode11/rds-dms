# ============================================================
# VARIABLES: UAT Environment
# ============================================================

variable "db_username" {
  description = "Master username for the UAT RDS instance"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the UAT RDS instance"
  type        = string
  sensitive   = true
  # Pass via: terraform apply -var="db_password=<PASSWORD>"
}

variable "source_password" {
  description = "Password for source EC2 SQL Server 2016 DMS endpoint"
  type        = string
  sensitive   = true
  # Pass via: terraform apply -var="source_password=<PASSWORD>"
}
