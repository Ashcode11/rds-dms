# ============================================================
# ENVIRONMENT: DEV
# Region:      us-west-2
# AZ:          us-west-2a (single AZ, no HA)
# Instance:    db.r5.4xlarge
# Purpose:     Developer testing environment
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
    key            = "dev/rds/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "<TERRAFORM_LOCK_TABLE>"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-west-2"
}

# ----------------------------------------------------------------
# DEV — RDS SQL Server 2022 SE
# Single AZ: us-west-2a | No HA | 2 TB gp3
# ----------------------------------------------------------------
module "rds_dev" {
  source = "../../modules/rds"

  identifier     = "gga-dev-mssql"
  instance_class = "db.r5.4xlarge"

  db_username = var.db_username
  db_password = var.db_password

  license_model = "license-included"

  # Storage
  allocated_storage     = 2048   # 2 TB
  max_allocated_storage = 4096   # 4 TB ceiling
  iops                  = 0      # gp3 default (3000 IOPS)

  # Network — replace placeholders with actual subnet/SG IDs
  subnet_ids          = ["<DEV_SUBNET_ID_AZ_A>"]  # us-west-2a subnet
  security_group_ids  = ["<DEV_RDS_SG_ID>"]

  # AZ — single AZ, no HA
  multi_az          = false
  availability_zone = "us-west-2a"

  # Backup
  backup_retention_days       = 7
  backup_restore_iam_role_arn = "<RDS_S3_BACKUP_RESTORE_ROLE_ARN>"

  # Monitoring
  monitoring_role_arn = "<RDS_ENHANCED_MONITORING_ROLE_ARN>"
  pi_retention_days   = 7

  # Lifecycle
  deletion_protection  = false
  skip_final_snapshot  = true

  tags = {
    Environment = "dev"
    Project     = "GGA-MSSQL-Migration"
    ManagedBy   = "Terraform"
    Owner       = "Nagarro"
  }
}
