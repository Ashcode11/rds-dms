# ============================================================
# MODULE: backup
# Provisions AWS Backup plan, vault, and selection for RDS.
# Uses AWS managed KMS key (aws/backup).
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
# Backup Vault
# ------------------------------------------------------------
resource "aws_backup_vault" "this" {
  name = "${var.identifier}-backup-vault"
  # kms_key_arn not set → uses AWS managed key (aws/backup)

  tags = merge(var.tags, { Name = "${var.identifier}-backup-vault" })
}

# ------------------------------------------------------------
# Backup Plan
# ------------------------------------------------------------
resource "aws_backup_plan" "this" {
  name = "${var.identifier}-backup-plan"

  # Daily backup rule
  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 2 * * ? *)"   # 02:00 UTC daily
    start_window      = 60                     # minutes after schedule
    completion_window = 180

    lifecycle {
      delete_after = var.backup_retention_days  # 7 (nonprod) / 35 (prod)
    }

    # Cross-region copy for prod only
    dynamic "copy_action" {
      for_each = var.enable_cross_region_copy ? [1] : []
      content {
        destination_vault_arn = var.dr_vault_arn   # <DR_BACKUP_VAULT_ARN_IN_SECONDARY_REGION>
        lifecycle {
          delete_after = var.cross_region_retention_days  # 90 days
        }
      }
    }
  }

  # Weekly backup rule (prod only)
  dynamic "rule" {
    for_each = var.enable_weekly_backup ? [1] : []
    content {
      rule_name         = "weekly-backup"
      target_vault_name = aws_backup_vault.this.name
      schedule          = "cron(0 3 ? * SUN *)"   # Every Sunday 03:00 UTC
      start_window      = 60
      completion_window = 300

      lifecycle {
        delete_after = 90
      }
    }
  }

  tags = merge(var.tags, { Name = "${var.identifier}-backup-plan" })
}

# ------------------------------------------------------------
# Backup Selection — tag-based targeting of RDS instances
# ------------------------------------------------------------
resource "aws_backup_selection" "this" {
  name         = "${var.identifier}-backup-selection"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = var.backup_role_arn   # <AWS_BACKUP_IAM_ROLE_ARN>

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "BackupPlan"
    value = var.identifier
  }
}
