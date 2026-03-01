# ============================================================
# VARIABLES: DEV Environment
# ============================================================

variable "db_username" {
  description = "Master username for the DEV RDS instance"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the DEV RDS instance"
  type        = string
  sensitive   = true
  # Pass via: terraform apply -var="db_password=<PASSWORD>"
}
