# ============================================================
# ENVIRONMENT: nonprod
# Deploys DEV, QA, and INT/UAT RDS SQL Server 2022 instances
# and a shared DMS replication instance.
# Uses EXISTING VPC, subnets, and security groups.
# ============================================================

locals {
  env = "nonprod"
  common_tags = {
    Project     = "mssql-migration"
    Environment = local.env
    ManagedBy   = "terraform"
  }
}

# ------------------------------------------------------------
# DEV — 21 DBs / 2.13 TB / Single AZ
# ------------------------------------------------------------
module "rds_dev" {
  source = "../../modules/rds"

  identifier     = "gga-dev-mssql"
  instance_class = "db.r5.4xlarge"
  license_model  = "bring-your-own-license"

  # Storage
  allocated_storage     = 2200    # 2.2 TB
  max_allocated_storage = 3072    # 3 TB ceiling
  iops                  = 0       # gp3 default

  # Network — REPLACE with actual IDs
  subnet_ids         = ["<NONPROD_SUBNET_ID_AZ_A>", "<NONPROD_SUBNET_ID_AZ_B>"]
  security_group_ids = ["<NONPROD_RDS_SG_ID>"]

  # HA
  multi_az = false

  # Auth
  db_username = "admin"
  db_password = var.db_password

  # Backup
  backup_retention_days      = 7
  backup_restore_iam_role_arn = "<RDS_S3_BACKUP_RESTORE_ROLE_ARN>"

  # Monitoring
  monitoring_role_arn = "<RDS_ENHANCED_MONITORING_ROLE_ARN>"
  pi_retention_days   = 7

  # Lifecycle
  deletion_protection  = false
  skip_final_snapshot  = true

  tags = merge(local.common_tags, { Env = "dev" })
}

# ------------------------------------------------------------
# QA — 21 DBs / 3.11 TB / Single AZ
# ------------------------------------------------------------
module "rds_qa" {
  source = "../../modules/rds"

  identifier     = "gga-qa-mssql"
  instance_class = "db.r5.4xlarge"
  license_model  = "bring-your-own-license"

  # Storage
  allocated_storage     = 3200    # 3.2 TB
  max_allocated_storage = 4096    # 4 TB ceiling
  iops                  = 0

  # Network — REPLACE with actual IDs
  subnet_ids         = ["<NONPROD_SUBNET_ID_AZ_A>", "<NONPROD_SUBNET_ID_AZ_B>"]
  security_group_ids = ["<NONPROD_RDS_SG_ID>"]

  # HA
  multi_az = false

  # Auth
  db_username = "admin"
  db_password = var.db_password

  # Backup
  backup_retention_days       = 7
  backup_restore_iam_role_arn = "<RDS_S3_BACKUP_RESTORE_ROLE_ARN>"

  # Monitoring
  monitoring_role_arn = "<RDS_ENHANCED_MONITORING_ROLE_ARN>"
  pi_retention_days   = 7

  # Lifecycle
  deletion_protection = false
  skip_final_snapshot = true

  tags = merge(local.common_tags, { Env = "qa" })
}

# ------------------------------------------------------------
# INT/UAT — 13 DBs / 1.30 TB / Multi-AZ (mirrors prod behaviour)
# ------------------------------------------------------------
module "rds_intuat" {
  source = "../../modules/rds"

  identifier     = "gga-intuat-mssql"
  instance_class = "db.r6i.8xlarge"
  license_model  = "bring-your-own-license"

  # Storage
  allocated_storage     = 1400    # 1.4 TB
  max_allocated_storage = 2048    # 2 TB ceiling
  iops                  = 0

  # Network — REPLACE with actual IDs
  subnet_ids         = ["<NONPROD_SUBNET_ID_AZ_A>", "<NONPROD_SUBNET_ID_AZ_B>"]
  security_group_ids = ["<NONPROD_RDS_SG_ID>"]

  # HA — Multi-AZ on to mirror prod behaviour for UAT testing
  multi_az = true

  # Auth
  db_username = "admin"
  db_password = var.db_password

  # Backup
  backup_retention_days       = 14
  backup_restore_iam_role_arn = "<RDS_S3_BACKUP_RESTORE_ROLE_ARN>"

  # Monitoring
  monitoring_role_arn = "<RDS_ENHANCED_MONITORING_ROLE_ARN>"
  pi_retention_days   = 7

  # Lifecycle
  deletion_protection = false
  skip_final_snapshot = true

  tags = merge(local.common_tags, { Env = "intuat" })
}

# ------------------------------------------------------------
# Shared DMS instance — Full Load only for nonprod
# Reused sequentially for DEV → QA → INT/UAT migrations
# ------------------------------------------------------------
module "dms_nonprod" {
  source = "../../modules/dms"

  identifier                 = "gga-nonprod"
  replication_instance_class = "dms.r5.2xlarge"
  allocated_storage          = 100

  # Network — REPLACE with actual IDs
  subnet_ids         = ["<NONPROD_SUBNET_ID_AZ_A>", "<NONPROD_SUBNET_ID_AZ_B>"]
  security_group_ids = ["<NONPROD_DMS_SG_ID>"]

  migration_type = "full-load"

  # Source — EC2 SQL Server 2016
  source_server_name   = "<SOURCE_EC2_PRIVATE_IP>"
  source_database_name = "<SOURCE_DB_NAME>"
  source_username      = "<SOURCE_DB_USERNAME>"
  source_password      = var.source_password
  source_schema        = "dbo"

  # Target — RDS DEV (update per wave: dev → qa → intuat endpoint)
  target_server_name   = module.rds_dev.db_address
  target_database_name = "<TARGET_DB_NAME>"
  target_username      = "admin"
  target_password      = var.db_password

  tags = merge(local.common_tags, { Component = "dms" })
}

# ------------------------------------------------------------
# AWS Backup — NonProd
# ------------------------------------------------------------
module "backup_nonprod" {
  source = "../../modules/backup"

  identifier            = "gga-nonprod"
  backup_retention_days = 7
  enable_weekly_backup  = false
  enable_cross_region_copy = false
  backup_role_arn       = "<AWS_BACKUP_ROLE_ARN>"

  tags = local.common_tags
}
