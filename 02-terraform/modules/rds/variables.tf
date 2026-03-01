# ============================================================
# MODULE VARIABLES: rds
# ============================================================

variable "identifier" {
  description = "Unique identifier for the RDS instance (e.g. gga-prod-mssql, gga-dev-mssql)"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class. Prod: db.r6i.16xlarge | NonProd: db.r5.4xlarge"
  type        = string
  # Example values:
  # prod    → "db.r6i.16xlarge"
  # nonprod → "db.r5.4xlarge"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the RDS instance. Use Secrets Manager in production."
  type        = string
  sensitive   = true
  # Replace with: data.aws_secretsmanager_secret_version.rds_password.secret_string
}

variable "license_model" {
  description = "SQL Server license model: license-included or bring-your-own-license"
  type        = string
  default     = "bring-your-own-license"
  # Options: "license-included" | "bring-your-own-license"
}

# ---- Storage ----
variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  # Prod: 13312 (13 TB) | NonProd: 2048–4096
}

variable "max_allocated_storage" {
  description = "Maximum storage autoscaling ceiling in GB"
  type        = number
  # Prod: 15360 (15 TB) | NonProd: 5120
}

variable "iops" {
  description = "Provisioned IOPS for gp3 (0 = use gp3 default 3000)"
  type        = number
  default     = 0
}

# ---- Network (Existing Resources) ----
variable "subnet_ids" {
  description = "List of EXISTING subnet IDs for the DB subnet group"
  type        = list(string)
  # Example: ["subnet-<ID1>", "subnet-<ID2>"]
}

variable "security_group_ids" {
  description = "List of EXISTING security group IDs to attach to the RDS instance"
  type        = list(string)
  # Example: ["sg-<RDS_SG_ID>"]
}

# ---- HA ----
variable "multi_az" {
  description = "Enable Multi-AZ deployment. true = prod/UAT | false = DEV/QA"
  type        = bool
  default     = false
}

variable "availability_zone" {
  description = "Preferred AZ for single-AZ instances (e.g. us-west-2a). Ignored when multi_az = true."
  type        = string
  default     = null
  # DEV / QA → "us-west-2a"
  # UAT / Prod → null (Multi-AZ, AWS manages AZ selection)
}

# ---- Backup ----
variable "backup_retention_days" {
  description = "Automated backup retention period in days (7 nonprod / 35 prod)"
  type        = number
  default     = 7
}

variable "backup_restore_iam_role_arn" {
  description = "IAM role ARN that allows RDS to access S3 for backup/restore"
  type        = string
  # Example: "arn:aws:iam::<ACCOUNT_ID>:role/rds-s3-backup-restore-role"
}

# ---- Monitoring ----
variable "monitoring_role_arn" {
  description = "IAM role ARN for RDS Enhanced Monitoring"
  type        = string
  # Example: "arn:aws:iam::<ACCOUNT_ID>:role/rds-enhanced-monitoring-role"
}

variable "pi_retention_days" {
  description = "Performance Insights retention in days (7 nonprod / 731 prod)"
  type        = number
  default     = 7
}

# ---- Lifecycle ----
variable "deletion_protection" {
  description = "Enable deletion protection. Always true for prod."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy. false for prod."
  type        = bool
  default     = true
}

# ---- Tags ----
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
