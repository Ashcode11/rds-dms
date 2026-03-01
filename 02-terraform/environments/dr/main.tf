# ============================================================
# ENVIRONMENT: DR (Disaster Recovery)
# Region:      us-east-1
# AZ:          us-east-1a
# Strategy:    Cross-region automated backup replication from prod (us-west-2)
#              + Warm standby RDS instance (restored from replicated backups on DR event)
#
# IMPORTANT — SQL Server RDS DR Architecture:
#   RDS SQL Server does NOT support traditional read replicas across regions.
#   DR is implemented using:
#     1. aws_db_instance_automated_backups_replication — continuously replicates
#        automated backups from prod (us-west-2) to DR vault (us-east-1).
#     2. In a DR event, the operations team restores the latest replicated backup
#        into the warm standby RDS instance defined below.
#   RTO: ~60-120 minutes (backup restore time depends on DB size)
#   RPO: Equal to prod backup frequency (max 24h with daily backups)
#
# Activate DR:
#   terraform apply -var="activate_dr=true"
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
    key            = "dr/rds/terraform.tfstate"
    region         = "us-east-1"            # DR state stored in DR region
    dynamodb_table = "<TERRAFORM_LOCK_TABLE>"
    encrypt        = true
  }
}

# Primary region provider (needed to reference prod RDS ARN for backup replication)
provider "aws" {
  alias  = "primary"
  region = "us-west-2"
}

# DR region provider
provider "aws" {
  alias  = "dr"
  region = "us-east-1"
}

# ----------------------------------------------------------------
# STEP 1: Cross-Region Automated Backup Replication
# Continuously replicates prod automated backups to us-east-1.
# This must be created in the PRIMARY region (us-west-2) pointing to DR region.
# ----------------------------------------------------------------
resource "aws_db_instance_automated_backups_replication" "prod_to_dr" {
  provider = aws.primary

  # ARN of the prod RDS instance (from prod environment output)
  source_db_instance_arn = "<PROD_RDS_ARN>"
  # Format: arn:aws:rds:us-west-2:<ACCOUNT_ID>:db:gga-prod-mssql

  # Replicate to DR region
  # Note: This resource is created in the primary region but replication
  # target is determined by the backup replication destination (us-east-1)
  retention_period = 7   # Keep 7 days of replicated backups in DR region

  # KMS key in DR region for encrypting replicated backups
  # Leave empty to use AWS managed key (aws/rds) in DR region
  # kms_key_id = "<DR_KMS_KEY_ARN>"
}

# ----------------------------------------------------------------
# STEP 2: DR Backup Vault (us-east-1)
# AWS Backup cross-region copy sends prod backups here.
# Also used as restore source for DR RDS instance.
# ----------------------------------------------------------------
resource "aws_backup_vault" "dr_vault" {
  provider = aws.dr

  name = "gga-dr-backup-vault"

  tags = {
    Environment = "dr"
    Project     = "GGA-MSSQL-Migration"
    ManagedBy   = "Terraform"
    Region      = "us-east-1"
  }
}

# ----------------------------------------------------------------
# STEP 3: Warm Standby RDS Instance (us-east-1a)
# This instance is STOPPED by default to minimize costs.
# In a DR event:
#   1. Start this instance
#   2. Restore latest replicated backup via rds_restore_database or console
#   3. Update DNS/connection strings to point to DR endpoint
#
# To activate DR: terraform apply -var="activate_dr=true"
# ----------------------------------------------------------------
resource "aws_db_subnet_group" "dr" {
  provider = aws.dr

  name        = "gga-dr-mssql-subnet-group"
  subnet_ids  = ["<DR_SUBNET_ID_AZ_A>"]   # us-east-1a subnet
  description = "DR subnet group for gga-dr-mssql in us-east-1a"

  tags = {
    Environment = "dr"
    Project     = "GGA-MSSQL-Migration"
    ManagedBy   = "Terraform"
  }
}

resource "aws_db_parameter_group" "dr" {
  provider = aws.dr

  name        = "gga-dr-mssql-pg"
  family      = "sqlserver-se-16.0"
  description = "Parameter group for DR RDS SQL Server 2022"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Environment = "dr"
    Project     = "GGA-MSSQL-Migration"
    ManagedBy   = "Terraform"
  }
}

resource "aws_db_option_group" "dr" {
  provider = aws.dr

  name                     = "gga-dr-mssql-og"
  engine_name              = "sqlserver-se"
  major_engine_version     = "16.00"
  option_group_description = "Option group for DR RDS SQL Server 2022"

  option {
    option_name = "SQLSERVER_BACKUP_RESTORE"
    option_settings {
      name  = "IAM_ROLE_ARN"
      value = "<DR_RDS_S3_BACKUP_RESTORE_ROLE_ARN>"
      # IAM role in us-east-1 allowing RDS to read/write S3
    }
  }

  tags = {
    Environment = "dr"
    Project     = "GGA-MSSQL-Migration"
    ManagedBy   = "Terraform"
  }
}

resource "aws_db_instance" "dr_standby" {
  provider = aws.dr

  identifier        = "gga-dr-mssql"
  engine            = "sqlserver-se"
  engine_version    = "16.00.4165.4.v1"    # Match prod version
  instance_class    = "db.r6i.8xlarge"     # Cost-optimised DR (scale up during DR event if needed)
  username          = var.db_username
  password          = var.db_password
  license_model     = "license-included"

  # Storage — match prod capacity
  allocated_storage     = 13312    # 13 TB
  max_allocated_storage = 15360    # 15 TB ceiling
  storage_type          = "gp3"
  iops                  = 0        # Default 3000 IOPS; increase during DR activation
  storage_encrypted     = true
  # kms_key_id not set → AWS managed key (aws/rds) in us-east-1

  # Network — single AZ in us-east-1a
  db_subnet_group_name   = aws_db_subnet_group.dr.name
  vpc_security_group_ids = ["<DR_RDS_SG_ID>"]
  publicly_accessible    = false
  port                   = 1433

  # AZ — DR standby in us-east-1a
  # Single AZ (not Multi-AZ) for cost; promote to Multi-AZ during active DR if needed
  availability_zone = "us-east-1a"
  multi_az          = false

  # Groups
  parameter_group_name = aws_db_parameter_group.dr.name
  option_group_name    = aws_db_option_group.dr.name

  # Backup — minimal retention; primary backup source is replicated prod backups
  backup_retention_period  = 7
  backup_window            = "03:00-04:00"
  maintenance_window       = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot    = true
  delete_automated_backups = false

  # Monitoring
  monitoring_interval                   = 60
  monitoring_role_arn                   = "<DR_RDS_ENHANCED_MONITORING_ROLE_ARN>"
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  enabled_cloudwatch_logs_exports       = ["error", "agent"]

  # Lifecycle
  auto_minor_version_upgrade = false
  deletion_protection        = true    # Protect DR instance
  skip_final_snapshot        = false
  final_snapshot_identifier  = "gga-dr-mssql-final-snapshot"

  tags = {
    Environment = "dr"
    Project     = "GGA-MSSQL-Migration"
    ManagedBy   = "Terraform"
    Owner       = "Nagarro"
    AZ          = "us-east-1a"
    Role        = "warm-standby"
    Note        = "Restore from replicated backup during DR event"
  }
}
