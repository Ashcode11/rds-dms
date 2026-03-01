# ============================================================
# ENVIRONMENT: UAT (INT / User Acceptance Testing)
# Region:      us-west-2
# AZs:         us-west-2a (primary) + us-west-2b (standby)
# HA:          Multi-AZ ENABLED (synchronous standby)
# Instance:    db.r6i.8xlarge
# Purpose:     Pre-production / UAT / Integration testing
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    bucket         = "<TERRAFORM_STATE_BUCKET>"
    key            = "uat/rds/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "<TERRAFORM_LOCK_TABLE>"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-west-2"
}

# ----------------------------------------------------------------
# UAT — RDS SQL Server 2022 SE
# Multi-AZ: us-west-2a (primary) + us-west-2b (standby)
# HA enabled — synchronous replication to standby
# 4 TB gp3 | db.r6i.8xlarge
# ----------------------------------------------------------------
module "rds_uat" {
  source = "../../modules/rds"

  identifier     = "gga-uat-mssql"
  instance_class = "db.r6i.8xlarge"

  db_username = var.db_username
  db_password = var.db_password

  license_model = "license-included"

  # Storage
  allocated_storage     = 4096    # 4 TB
  max_allocated_storage = 8192    # 8 TB ceiling
  iops                  = 6000    # 6000 IOPS for UAT workload

  # Network — subnets in BOTH AZs required for Multi-AZ
  # Replace with actual subnet IDs in us-west-2a and us-west-2b
  subnet_ids         = [
    "<UAT_SUBNET_ID_AZ_A>",   # us-west-2a (primary)
    "<UAT_SUBNET_ID_AZ_B>"    # us-west-2b (standby)
  ]
  security_group_ids = ["<UAT_RDS_SG_ID>"]

  # HA — Multi-AZ enabled (us-west-2a primary, us-west-2b standby)
  # AWS automatically manages AZ placement for Multi-AZ; availability_zone is ignored
  multi_az          = true
  availability_zone = null   # Not applicable when multi_az = true

  # Backup
  backup_retention_days       = 14
  backup_restore_iam_role_arn = "<RDS_S3_BACKUP_RESTORE_ROLE_ARN>"

  # Monitoring
  monitoring_role_arn = "<RDS_ENHANCED_MONITORING_ROLE_ARN>"
  pi_retention_days   = 7

  # Lifecycle
  deletion_protection = false
  skip_final_snapshot = true

  tags = {
    Environment = "uat"
    Project     = "GGA-MSSQL-Migration"
    ManagedBy   = "Terraform"
    Owner       = "Nagarro"
    HA          = "Multi-AZ"
  }
}

# ----------------------------------------------------------------
# DMS — Replication for UAT (used during migration only)
# Native backup/restore is primary method for nonprod,
# but DMS instance is provisioned for mock cutover testing.
# ----------------------------------------------------------------
module "dms_uat" {
  source = "../../modules/dms"

  environment        = "uat"
  replication_class  = "dms.r5.2xlarge"
  az                 = "us-west-2a"
  subnet_ids         = [
    "<UAT_SUBNET_ID_AZ_A>",
    "<UAT_SUBNET_ID_AZ_B>"
  ]
  security_group_ids = ["<UAT_DMS_SG_ID>"]

  source_server_name = "<SOURCE_EC2_PRIVATE_IP>"
  source_password    = var.source_password

  target_endpoint_address  = module.rds_uat.db_instance_address
  target_password           = var.db_password

  migration_type = "full-load"    # UAT uses full-load for mock cutover

  tags = {
    Environment = "uat"
    Project     = "GGA-MSSQL-Migration"
    ManagedBy   = "Terraform"
    Owner       = "Nagarro"
  }
}
