# ============================================================
# VARIABLES: DR Environment
# ============================================================

variable "db_username" {
  description = "Master username for the DR RDS instance"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the DR RDS instance (use same as prod)"
  type        = string
  sensitive   = true
  # Pass via: terraform apply -var="db_password=<PASSWORD>"
}
