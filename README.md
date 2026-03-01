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
│       ├── dev/            # DEV — us-west-2a, single AZ, no HA
│       ├── qa/             # QA  — us-west-2a, single AZ, no HA
│       ├── uat/            # UAT — us-west-2a + us-west-2b, Multi-AZ (HA)
│       ├── prod/           # PROD — us-west-2a + us-west-2b, Multi-AZ (HA)
│       └── dr/             # DR  — us-east-1a, cross-region backup replication
├── 03-dms/                 # DMS migration configs and runbooks
│   ├── nonprod-backup-restore/   # Native backup/restore for nonprod
│   └── prod-dms-cdc/             # Full Load + CDC for production
├── 04-ha-dr/               # HA and DR configuration docs
├── 05-monitoring/          # CloudWatch alarms and dashboards
├── 06-scripts/             # Helper scripts (SQL, bash)
└── 07-runbooks/            # Step-by-step operational runbooks
```

## Environment Summary

| Environment | Region    | AZ(s)                      | HA       | Instance        | Migration Method      |
|-------------|-----------|----------------------------|----------|-----------------|-----------------------|
| DEV         | us-west-2 | us-west-2a                 | No       | db.r5.4xlarge   | Native backup → S3    |
| QA          | us-west-2 | us-west-2a                 | No       | db.r5.4xlarge   | Native backup → S3    |
| UAT         | us-west-2 | us-west-2a + us-west-2b    | Multi-AZ | db.r6i.8xlarge  | Native backup → S3    |
| PROD        | us-west-2 | us-west-2a + us-west-2b    | Multi-AZ | db.r6i.16xlarge | DMS Full Load + CDC   |
| DR          | us-east-1 | us-east-1a                 | Warm     | db.r6i.8xlarge  | Cross-region backup   |

## Migration Approach

| Environment | Method                              | Downtime         |
|-------------|-------------------------------------|------------------|
| DEV / QA    | Native backup → S3 → RDS restore   | Scheduled window |
| UAT         | Native backup → S3 → RDS restore   | Scheduled window |
| Production  | AWS DMS Full Load + CDC             | 120–240 min SLA  |
| DR          | Automated backup replication        | N/A (standby)    |

## HA & DR Design

- **DEV / QA**: Single AZ (us-west-2a), acceptable downtime for non-production
- **UAT**: Multi-AZ — primary in us-west-2a, synchronous standby in us-west-2b. Auto-failover ~60–120 sec RTO
- **Prod**: Multi-AZ — primary in us-west-2a, synchronous standby in us-west-2b. Auto-failover ~60–120 sec RTO
- **DR**: Cross-region backup replication (us-west-2 → us-east-1). Warm standby in us-east-1a activated on DR event. RTO ~60–120 min, RPO ~24h

## Key Tools

- **AWS SCT** — Schema assessment & conversion (EC2 Windows Server 2022, same VPC)
- **AWS DMS** — Data migration for production (Full Load + CDC)
- **Terraform** — Infrastructure provisioning (all environments)
- **AWS Backup** — Automated backup with cross-region DR copy to us-east-1

## Getting Started

### Prerequisites
- AWS CLI configured with appropriate IAM permissions
- Terraform >= 1.5.0
- Access to existing VPC, subnets, and security groups

### Deploy DEV
```bash
cd 02-terraform/environments/dev
terraform init
terraform plan -var="db_password=<PASSWORD>"
terraform apply -var="db_password=<PASSWORD>"
```

### Deploy QA
```bash
cd 02-terraform/environments/qa
terraform init
terraform plan -var="db_password=<PASSWORD>"
terraform apply -var="db_password=<PASSWORD>"
```

### Deploy UAT
```bash
cd 02-terraform/environments/uat
terraform init
terraform plan -var="db_password=<PASSWORD>" -var="source_password=<PASSWORD>"
terraform apply -var="db_password=<PASSWORD>" -var="source_password=<PASSWORD>"
```

### Deploy Prod
```bash
cd 02-terraform/environments/prod
terraform init
terraform plan -var="db_password=<PASSWORD>" -var="source_password=<PASSWORD>"
terraform apply -var="db_password=<PASSWORD>" -var="source_password=<PASSWORD>"
```

### Deploy DR
```bash
cd 02-terraform/environments/dr
terraform init
terraform plan -var="db_password=<PASSWORD>"
terraform apply -var="db_password=<PASSWORD>"
```

> **Note:** Replace all `<PLACEHOLDER>` values in `.tf` files with actual resource IDs before running.

## Placeholders Reference

All placeholders follow `<UPPERCASE_FORMAT>`. Key ones to replace:

| Placeholder | Description |
|---|---|
| `<AWS_REGION>` | Primary AWS region (us-west-2) |
| `<DR_REGION>` | DR region (us-east-1) |
| `<DEV_SUBNET_ID_AZ_A>` | Existing subnet in us-west-2a for DEV |
| `<QA_SUBNET_ID_AZ_A>` | Existing subnet in us-west-2a for QA |
| `<UAT_SUBNET_ID_AZ_A/B>` | Existing subnet IDs in us-west-2a and us-west-2b for UAT |
| `<PROD_SUBNET_ID_AZ_A/B>` | Existing subnet IDs in us-west-2a and us-west-2b for PROD |
| `<DR_SUBNET_ID_AZ_A>` | Existing subnet in us-east-1a for DR |
| `<PROD_RDS_SG_ID>` | Existing RDS security group ID (prod) |
| `<DR_RDS_SG_ID>` | Existing RDS security group ID (DR region) |
| `<PROD_DMS_SG_ID>` | Existing DMS security group ID |
| `<RDS_S3_BACKUP_RESTORE_ROLE_ARN>` | IAM role for RDS S3 backup/restore |
| `<RDS_ENHANCED_MONITORING_ROLE_ARN>` | IAM role for enhanced monitoring |
| `<AWS_BACKUP_ROLE_ARN>` | IAM role for AWS Backup |
| `<TERRAFORM_STATE_BUCKET>` | S3 bucket for Terraform state |
| `<TERRAFORM_LOCK_TABLE>` | DynamoDB table for state locking |
| `<SOURCE_EC2_PRIVATE_IP>` | Source SQL Server 2016 EC2 IP |
| `<PROD_RDS_ARN>` | ARN of prod RDS instance (for DR backup replication) |

---
*March 2026 | Nagarro*
