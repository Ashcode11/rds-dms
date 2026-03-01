variable "identifier" {
  description = "Identifier prefix for backup resources (e.g. gga-prod, gga-nonprod)"
  type        = string
}

variable "backup_retention_days" {
  description = "Number of days to retain daily backups (7 nonprod / 35 prod)"
  type        = number
  default     = 7
}

variable "enable_weekly_backup" {
  description = "Enable weekly backup rule (recommended for prod)"
  type        = bool
  default     = false
}

variable "enable_cross_region_copy" {
  description = "Enable cross-region backup copy to DR vault (prod only)"
  type        = bool
  default     = false
}

variable "dr_vault_arn" {
  description = "ARN of the DR region backup vault for cross-region copy"
  type        = string
  default     = ""
  # Example: "arn:aws:backup:<DR_REGION>:<ACCOUNT_ID>:backup-vault:<DR_VAULT_NAME>"
}

variable "cross_region_retention_days" {
  description = "Retention days for cross-region backup copies"
  type        = number
  default     = 90
}

variable "backup_role_arn" {
  description = "IAM role ARN for AWS Backup to use"
  type        = string
  # Example: "arn:aws:iam::<ACCOUNT_ID>:role/aws-backup-role"
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
