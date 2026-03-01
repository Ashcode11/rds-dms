# ============================================================
# ENVIRONMENT: prod
# Deploys Production RDS SQL Server 2022 (Multi-AZ primary)
# + DMS Full Load + CDC instance
# + AWS Backup with cross-region DR copy
# Uses EXISTING VPC, subnets, and security groups.
# ============================================================

locals {
  env = "prod"
  common_tags = {
    Project     = "mssql-migration"
    Environment = local.env
    ManagedBy   = "terraform"
    CostCenter  = "<COST_CENTER>"
  }
}

# ------------------------------------------------------------
# Production RDS — 15 DBs / ~11.22 TB / Multi-AZ
# db.r6i.16xlarge: 64 vCPU / 512 GiB RAM
# ------------------------------------------------------------
module "rds_prod" {
  source = "../../modules/rds"

  identifier     = "gga-prod-mssql"
  instance_class = "db.r6i.16xlarge"
  license_model  = "bring-your-own-license"

  # Storage — 13 TB with autoscaling to 15 TB
  allocated_storage     = 13312   # 13 TB in GB
  max_allocated_storage = 15360   # 15 TB ceiling
  iops                  = 0       # gp3 default 3000 IOPS; increase if needed

  # Network — REPLACE with actual existing resource IDs
  subnet_ids         = ["<PROD_SUBNET_ID_AZ_A>", "<PROD_SUBNET_ID_AZ_B>"]
  security_group_ids = ["<PROD_RDS_SG_ID>"]

  # HA — Multi-AZ required for production
  multi_az = true

  # Auth
  db_username = "admin"
  db_password = var.db_password

  # Backup
  backup_retention_days       = 35
  backup_restore_iam_role_arn = "<RDS_S3_BACKUP_RESTORE_ROLE_ARN>"

  # Monitoring
  monitoring_role_arn = "<RDS_ENHANCED_MONITORING_ROLE_ARN>"
  pi_retention_days   = 731   # 2 years for prod

  # Lifecycle — protect prod from accidental deletion
  deletion_protection = true
  skip_final_snapshot = false

  tags = merge(local.common_tags, {
    BackupPlan = "gga-prod"   # matches backup selection tag
  })
}

# ------------------------------------------------------------
# Production DMS — Full Load + CDC
# r5.4xlarge: 16 vCPU / 128 GiB, ~500 MB/s throughput
# ------------------------------------------------------------
module "dms_prod" {
  source = "../../modules/dms"

  identifier                 = "gga-prod"
  replication_instance_class = "dms.r5.4xlarge"
  allocated_storage          = 500   # GB

  # Network — REPLACE with actual existing resource IDs
  subnet_ids         = ["<PROD_DMS_SUBNET_ID_AZ_A>", "<PROD_DMS_SUBNET_ID_AZ_B>"]
  security_group_ids = ["<PROD_DMS_SG_ID>"]

  migration_type = "full-load-and-cdc"

  # Source — EC2 SQL Server 2016 (primary/listener IP)
  source_server_name   = "<SOURCE_PROD_EC2_LISTENER_IP>"
  source_database_name = "<SOURCE_PROD_DB_NAME>"
  source_username      = "<SOURCE_DB_USERNAME>"
  source_password      = var.source_password
  source_schema        = "dbo"

  # Target — Production RDS
  target_server_name   = module.rds_prod.db_address
  target_database_name = "<TARGET_PROD_DB_NAME>"
  target_username      = "admin"
  target_password      = var.db_password

  tags = merge(local.common_tags, { Component = "dms" })
}

# ------------------------------------------------------------
# AWS Backup — Production with cross-region DR copy
# ------------------------------------------------------------
module "backup_prod" {
  source = "../../modules/backup"

  identifier            = "gga-prod"
  backup_retention_days = 35
  enable_weekly_backup  = true
  enable_cross_region_copy    = true
  dr_vault_arn                = "<DR_BACKUP_VAULT_ARN>"   # arn:aws:backup:<DR_REGION>:<ACCOUNT_ID>:backup-vault:<VAULT_NAME>
  cross_region_retention_days = 90
  backup_role_arn             = "<AWS_BACKUP_ROLE_ARN>"

  tags = merge(local.common_tags, { BackupPlan = "gga-prod" })
}

# ------------------------------------------------------------
# Outputs
# ------------------------------------------------------------
output "prod_rds_endpoint" {
  description = "Production RDS endpoint — update app connection strings to this value"
  value       = module.rds_prod.db_endpoint
}

output "prod_rds_address" {
  description = "Production RDS hostname"
  value       = module.rds_prod.db_address
}

output "prod_dms_task_arn" {
  description = "Production DMS replication task ARN"
  value       = module.dms_prod.replication_task_arn
}
