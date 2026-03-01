# ============================================================
# MODULE: rds
# Provisions RDS SQL Server 2022 instance, parameter group,
# option group, and subnet group.
# Uses EXISTING VPC subnets and security groups.
# Encryption via AWS Managed KMS key (aws/rds).
# ============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ------------------------------------------------------------
# DB Subnet Group — uses existing subnets passed as variable
# ------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name        = "${var.identifier}-subnet-group"
  subnet_ids  = var.subnet_ids          # <EXISTING_SUBNET_IDS>
  description = "Subnet group for ${var.identifier} RDS SQL Server"

  tags = merge(var.tags, {
    Name = "${var.identifier}-subnet-group"
  })
}

# ------------------------------------------------------------
# Parameter Group — SQL Server 2022
# ------------------------------------------------------------
resource "aws_db_parameter_group" "this" {
  name        = "${var.identifier}-pg"
  family      = "sqlserver-se-16.0"     # SQL Server 2022 SE
  description = "Parameter group for ${var.identifier}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = merge(var.tags, { Name = "${var.identifier}-pg" })
}

# ------------------------------------------------------------
# Option Group — SQL Server 2022 (enables backup/restore via S3)
# ------------------------------------------------------------
resource "aws_db_option_group" "this" {
  name                     = "${var.identifier}-og"
  engine_name              = "sqlserver-se"
  major_engine_version     = "16.00"    # SQL Server 2022
  option_group_description = "Option group for ${var.identifier}"

  option {
    option_name = "SQLSERVER_BACKUP_RESTORE"
    option_settings {
      name  = "IAM_ROLE_ARN"
      value = var.backup_restore_iam_role_arn  # <IAM_ROLE_ARN_FOR_S3_BACKUP>
    }
  }

  tags = merge(var.tags, { Name = "${var.identifier}-og" })
}

# ------------------------------------------------------------
# RDS SQL Server 2022 Instance
# ------------------------------------------------------------
resource "aws_db_instance" "this" {
  identifier        = var.identifier
  engine            = "sqlserver-se"
  engine_version    = "16.00.4165.4.v1"   # SQL Server 2022 SE — update to latest
  instance_class    = var.instance_class   # e.g. db.r6i.16xlarge (prod) / db.r5.4xlarge (nonprod)
  username          = var.db_username      # <MASTER_USERNAME>
  password          = var.db_password      # <MASTER_PASSWORD> — use Secrets Manager in prod
  license_model     = var.license_model    # "license-included" or "bring-your-own-license"

  # Storage
  allocated_storage     = var.allocated_storage      # GB
  max_allocated_storage = var.max_allocated_storage  # autoscaling ceiling
  storage_type          = "gp3"
  iops                  = var.iops                   # 0 = default for gp3
  storage_encrypted     = true
  # kms_key_id not set → uses AWS managed key (aws/rds)

  # Network — existing VPC resources
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids    # <EXISTING_SECURITY_GROUP_IDS>
  publicly_accessible    = false
  port                   = 1433

  # High Availability
  multi_az = var.multi_az   # true for prod/INT-UAT, false for DEV/QA

  # Parameter & Option Groups
  parameter_group_name = aws_db_parameter_group.this.name
  option_group_name    = aws_db_option_group.this.name

  # Backup
  backup_retention_period   = var.backup_retention_days  # 7 (nonprod) / 35 (prod)
  backup_window             = "02:00-03:00"
  maintenance_window        = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false

  # Monitoring
  monitoring_interval             = 60   # Enhanced Monitoring — seconds
  monitoring_role_arn             = var.monitoring_role_arn  # <RDS_ENHANCED_MONITORING_ROLE_ARN>
  performance_insights_enabled    = true
  performance_insights_retention_period = var.pi_retention_days  # 7 (nonprod) / 731 (prod)
  enabled_cloudwatch_logs_exports = ["error", "agent"]

  # Misc
  auto_minor_version_upgrade  = false
  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = var.skip_final_snapshot ? null : "${var.identifier}-final-snapshot"
  timezone                    = "UTC"

  tags = merge(var.tags, { Name = var.identifier })
}
