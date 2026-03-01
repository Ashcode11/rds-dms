# RDS DMS Migration — GGA MSSQL Migration Project

Migration of Microsoft SQL Server 2016 (AWS EC2) to AWS RDS SQL Server 2022
**Client:** Generali Global Assistance | **Vendor:** Nagarro

---

## Project Structure

```
mssql-migration-project/
├── 01-architecture/        # Architecture docs and diagram descriptions
├── 02-terraform/           # Infrastructure as Code (Terraform)
│   ├── modules/
│   │   ├── rds/            # RDS SQL Server 2022 module
│   │   ├── dms/            # AWS DMS replication module
│   │   └── backup/         # AWS Backup module
│   └── environments/
│       ├── nonprod/        # DEV, QA, INT/UAT environments
│       └── prod/           # Production + DR environment
├── 03-dms/                 # DMS migration configs and runbooks
│   ├── nonprod-backup-restore/   # Native backup/restore for nonprod
│   └── prod-dms-cdc/             # Full Load + CDC for production
├── 04-ha-dr/               # HA and DR configuration docs
├── 05-monitoring/          # CloudWatch alarms and dashboards
├── 06-scripts/             # Helper scripts (SQL, bash)
└── 07-runbooks/            # Step-by-step operational runbooks
```

## Migration Approach

| Environment | Method | Downtime |
|---|---|---|
| DEV / QA | Native backup → S3 → RDS restore | Scheduled window |
| INT / UAT | Native backup → S3 → RDS restore | Scheduled window |
| Production | AWS DMS Full Load + CDC | 120–240 min SLA |

## Key Tools
- **AWS SCT** — Schema assessment & conversion (EC2 Windows Server 2022)
- **AWS DMS** — Data migration (Full Load + CDC)
- **Terraform** — Infrastructure provisioning
- **AWS Backup** — Automated backup with cross-region DR copy

## Getting Started

### Prerequisites
- AWS CLI configured with appropriate IAM permissions
- Terraform >= 1.5.0
- Access to existing VPC, subnets, and security groups

### Deploy NonProd
```bash
cd 02-terraform/environments/nonprod
terraform init
terraform plan -var="db_password=<PASSWORD>" -var="source_password=<PASSWORD>"
terraform apply
```

### Deploy Prod
```bash
cd 02-terraform/environments/prod
terraform init
terraform plan -var="db_password=<PASSWORD>" -var="source_password=<PASSWORD>"
terraform apply
```

> **Note:** Replace all `<PLACEHOLDER>` values in `.tf` files with actual resource IDs before running.

## Placeholders Reference
All placeholders follow `<UPPERCASE_FORMAT>`. Key ones to replace:

| Placeholder | Description |
|---|---|
| `<AWS_REGION>` | Primary AWS region (e.g. us-west-1) |
| `<AWS_DR_REGION>` | DR region (e.g. us-east-1) |
| `<PROD_SUBNET_ID_AZ_A/B>` | Existing subnet IDs in primary region |
| `<PROD_RDS_SG_ID>` | Existing RDS security group ID |
| `<PROD_DMS_SG_ID>` | Existing DMS security group ID |
| `<RDS_S3_BACKUP_RESTORE_ROLE_ARN>` | IAM role for RDS S3 backup/restore |
| `<RDS_ENHANCED_MONITORING_ROLE_ARN>` | IAM role for enhanced monitoring |
| `<AWS_BACKUP_ROLE_ARN>` | IAM role for AWS Backup |
| `<TERRAFORM_STATE_BUCKET>` | S3 bucket for Terraform state |
| `<TERRAFORM_LOCK_TABLE>` | DynamoDB table for state locking |
| `<SOURCE_EC2_PRIVATE_IP>` | Source SQL Server 2016 EC2 IP |

---
*March 2026 | Nagarro*
