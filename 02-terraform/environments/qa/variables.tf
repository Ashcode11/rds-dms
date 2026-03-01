# ============================================================
# VARIABLES: QA Environment
# ============================================================

variable "db_username" {
  description = "Master username for the QA RDS instance"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the QA RDS instance"
  type        = string
  sensitive   = true
  # Pass via: terraform apply -var="db_password=<PASSWORD>"
}
