# Architecture Document — MSSQL Migration
## EC2 SQL Server 2016 → AWS RDS SQL Server 2022
**Client:** Generali Global Assistance (GGA) | **Vendor:** Nagarro | **Date:** March 2026
**Regions:** Primary — US-West-1 | DR — US-East-1

---

## Table of Contents
1. [Overview](#1-overview)
2. [VPC & Subnet Design](#2-vpc--subnet-design)
3. [RDS Multi-AZ Setup (Production)](#3-rds-multi-az-setup-production)
4. [DMS Replication Instances](#4-dms-replication-instances)
5. [Backup & Restore Strategy — Non-Production](#5-backup--restore-strategy--non-production)
6. [Full Load + CDC — Production Migration](#6-full-load--cdc--production-migration)
7. [CloudWatch Monitoring](#7-cloudwatch-monitoring)
8. [Security & IAM Boundaries](#8-security--iam-boundaries)
9. [Component Reference](#9-component-reference)

---

## 1. Overview

GGA runs a 3-node SQL Server 2016 Always On Availability Group on AWS EC2, hosting 15 production databases (~11.22 TB) plus non-production environments across DEV, QA, and INT/UAT. The target state is Amazon RDS for SQL Server 2022 with Multi-AZ HA in US-West and a warm DR standby in US-East.

**Migration approach:** AWS DMS Full Load + CDC (Option B — minimal downtime). Non-production environments use native backup/restore via S3.

**Schema conversion:** AWS Schema Conversion Tool (SCT) installed on a dedicated EC2 Windows Server 2022 instance within the same VPC. SCT performs compatibility assessment, auto-converts schema objects, and applies the converted DDL directly to the target RDS before DMS tasks begin.

### Environment Inventory

| Environment | EC2 Source IP(s) | DBs | Size | Target Instance | Multi-AZ |
|---|---|---|---|---|---|
| DEV | 101.x.x.228 | 21 | 2.13 TB | db.r5.4xlarge | No |
| QA | 62.x.x.228 | 21 | 3.11 TB | db.r5.4xlarge | No |
| INT/UAT | 101.x.x.228 | 13 | 1.30 TB | db.r6i.8xlarge | Yes |
| Production | 15.x.181 / 7.x.100 / 7.x.228 | 15 | ~11.22 TB | db.r6i.16xlarge | Yes (+ DR) |

---

## 2. VPC & Subnet Design

All environments share a single VPC (`10.0.0.0/16`) with strict subnet segmentation. Production and non-production use separate subnet groups, security groups, and KMS keys.

### Subnet Layout

```
VPC: 10.0.0.0/16  (US-West-1)
│
├── Public Subnets
│   ├── 10.0.0.0/24  (AZ-A)   — Internet GW, NAT GW, ALB
│   └── 10.0.16.0/24 (AZ-B)   — Internet GW, NAT GW, ALB
│
├── Private App Subnets
│   ├── 10.0.1.0/24  (AZ-A)   — Application servers (SG: app-sg)
│   └── 10.0.17.0/24 (AZ-B)   — Application servers (SG: app-sg)
│
├── RDS Production Subnets  (DB Subnet Group: rds-prod-subnet-group)
│   ├── 10.0.2.0/24  (AZ-A)   — RDS Primary
│   └── 10.0.18.0/24 (AZ-B)   — RDS Multi-AZ Standby
│
├── RDS Non-Prod Subnets  (DB Subnet Group: rds-nonprod-subnet-group)
│   ├── 10.0.3.0/24  (AZ-A)   — DEV / QA / INT-UAT instances
│   └── 10.0.19.0/24 (AZ-B)   — INT-UAT standby
│
├── DMS Subnets  (DMS Replication Subnet Group: dms-subnet-group)
│   ├── 10.0.4.0/24  (AZ-A)   — DMS replication instance (prod)
│   └── 10.0.20.0/24 (AZ-B)   — DMS (non-prod, same instance reused)
│
└── Management Subnet
    └── 10.0.5.0/24  (AZ-A)   — Bastion (SSM only), VPC Interface Endpoints
```

### VPC Endpoints (PrivateLink — no internet traversal)

All service calls from within the VPC use Interface Endpoints so that no traffic leaves the AWS backbone:

- `com.amazonaws.us-west-1.s3` (Gateway endpoint)
- `com.amazonaws.us-west-1.kms`
- `com.amazonaws.us-west-1.secretsmanager`
- `com.amazonaws.us-west-1.logs` (CloudWatch Logs)
- `com.amazonaws.us-west-1.monitoring`
- `com.amazonaws.us-west-1.ssm` and `ssmmessages`
- `com.amazonaws.us-west-1.dms`

### Security Group Matrix

| Security Group | Inbound | Outbound | Attached To |
|---|---|---|---|
| `app-sg` | HTTPS 443 from ALB-sg; custom app port | TCP 1433 → `rds-proxy-sg` | Application servers |
| `rds-proxy-sg` | TCP 1433 from `app-sg` | TCP 1433 → `rds-sg` | RDS Proxy ×3 |
| `rds-sg` | TCP 1433 from `rds-proxy-sg`, `dms-sg`, `bastion-sg` | None required | RDS Primary & Standby |
| `dms-sg` | None (no inbound) | TCP 1433 → `rds-sg`; HTTPS 443 → VPC endpoints | DMS Replication Instance |
| `bastion-sg` | None (SSM Session Manager only) | TCP 1433 → `rds-sg` (admin) | Bastion Host |

---

## 3. RDS Multi-AZ Setup (Production)

### Architecture

```
US-West-1 (Production VPC)
│
├── AZ-A: RDS SQL Server 2022 — PRIMARY
│   ├── Instance: db.r6i.16xlarge (64 vCPU / 512 GiB RAM)
│   ├── Storage: gp3 — 13 TB, 3,000 IOPS, 125 MB/s throughput
│   ├── Storage autoscaling: enabled (ceiling 15 TB)
│   ├── Encryption: KMS CMK (prod-rds-key)
│   ├── TLS: enforced (rds.force_ssl = 1)
│   └── Handles all READ / WRITE workloads
│
├── AZ-B: RDS SQL Server 2022 — MULTI-AZ STANDBY (RDS-managed)
│   ├── Instance: db.r6i.16xlarge (identical spec)
│   ├── Synchronous replication from Primary
│   ├── Not directly accessible (pure HA — not a read replica)
│   └── Automatic DNS failover within 60–120 seconds on primary failure
│
└── RDS Proxy (×3 instances)
    ├── Maintains persistent connection pool to primary endpoint
    ├── IAM authentication enforced
    ├── Buffers application connections during failover
    └── Exposes single stable endpoint to applications
```

### RDS Parameter Group (prod-sql2022-pg)

| Parameter | Value | Reason |
|---|---|---|
| `max server memory (MB)` | 507,904 (~496 GB) | Leaves 16 GB for OS buffer |
| `max degree of parallelism` | 4 | OLTP optimal for this workload |
| `cost threshold for parallelism` | 50 | Prevents over-parallelisation |
| `optimize for ad hoc workloads` | 1 | Reduces plan cache bloat |
| `rds.force_ssl` | 1 | Enforces TLS on all connections |
| `tempdb` files | 8 (equal size) | Reduces allocation contention |

### RDS Option Group (prod-sql2022-og)

| Option | Purpose |
|---|---|
| `SQLSERVER_BACKUP_RESTORE` | Enables S3-based native backup/restore (used for non-prod) |
| `SQLSERVER_AUDIT` | SQL Server Audit feature for compliance logging |

### Multi-AZ Failover Behaviour

1. RDS detects primary failure (hardware fault, storage failure, or AZ outage).
2. RDS promotes the Multi-AZ standby to primary automatically.
3. RDS endpoint DNS record is updated — applications reconnect within ~30 s (TTL 30 s).
4. RDS Proxy absorbs connection retries during the DNS propagation window.
5. CloudWatch Event → EventBridge → SNS → PagerDuty fires `rds-failover-event` alarm.
6. RDS provisions a new standby in the original AZ to restore Multi-AZ protection.

---

## 4. DMS Replication Instances

### Production DMS Instance

| Parameter | Value |
|---|---|
| Instance class | `r5.4xlarge` (16 vCPU / 128 GiB) |
| Storage | 500 GB SSD (task cache and log staging) |
| Multi-AZ | No (DMS instance is stateless; failure means restart, not data loss) |
| VPC / Subnet | `dms-subnet-group` (private, no internet) |
| Security Group | `dms-sg` |
| KMS | Uses `prod-rds-key` to encrypt task logs |

### Non-Production DMS Instance

| Parameter | Value |
|---|---|
| Instance class | `r5.2xlarge` (8 vCPU / 64 GiB) |
| Reuse | Single instance reused sequentially for DEV → QA → INT/UAT (full-load only) |
| Lifecycle | Provisioned before Wave 2; terminated after Wave 4 completes |

### DMS Source Endpoint (EC2 SQL Server 2016)

```yaml
engine:            sqlserver
server:            <EC2_PRIMARY_IP>
port:              1433
database:          <target_db>
auth:              username/password (stored in Secrets Manager)
extra_connection_attributes:
  - useBcpFullLoad=Y          # faster full load via BCP
  - parallelLoadThreads=8     # parallel table loading
  - BCPPacketSize=32768
CDC prerequisites on source:
  - CDC enabled:  EXEC sys.sp_cdc_enable_db
  - Log retention: >= 24 hours (exec sp_configure 'Agent XPs')
  - DMS user:      db_owner OR SELECT + EXECUTE on CDC tables
```

### DMS Target Endpoint (RDS SQL Server 2022)

```yaml
engine:            sqlserver
server:            <RDS_ENDPOINT>
port:              1433
database:          <target_db>
auth:              IAM + Secrets Manager rotation
extra_connection_attributes:
  - parallelApplyThreads=8
  - parallelApplyBufferSize=1000
```

### DMS Task Configuration

| Task Phase | Type | Tables | LOB Mode | Expected Duration |
|---|---|---|---|---|
| Full Load | `full-load` | All 15 prod DBs | Limited LOB (64 KB) | ~7 hrs @ 500 MB/s |
| CDC | `cdc` | All 15 prod DBs | — | Continuous until cutover |
| Non-Prod | `full-load` | Per environment | Limited LOB | 2–6 hrs per env |

### DMS CloudWatch Alarms (per task)

- `CDCLatency > 60 seconds` → SNS alert
- `TaskErrorCount > 0` → EventBridge → Lambda notify
- `FullLoadRowsInserted` stalls for 10 min → SNS alert

---

## 5. Backup & Restore Strategy — Non-Production

Non-production environments (DEV, QA, INT/UAT) use **native SQL Server backup via S3** — the simplest, most deterministic path for workloads that can tolerate a brief maintenance window.

### Backup/Restore Flow

```
EC2 Source (SQL Server 2016)
    │
    ├── 1. BACKUP DATABASE [dbname] TO DISK='\\share\backup.bak'
    │      WITH COMPRESSION, CHECKSUM
    │
    ├── 2. aws s3 cp backup.bak s3://gga-migration-nonprod/env/dbname/
    │
RDS Target (SQL Server 2022)
    │
    ├── 3. EXEC msdb.dbo.rds_restore_database
    │         @restore_db_name = 'dbname',
    │         @s3_arn_to_restore_from = 'arn:aws:s3:::gga-migration-nonprod/env/dbname/backup.bak'
    │
    ├── 4. EXEC msdb.dbo.rds_task_status   -- monitor progress
    │
    └── 5. Post-restore:
           - ALTER DATABASE [dbname] SET COMPATIBILITY_LEVEL = 160  (SQL 2022)
           - UPDATE STATISTICS (all tables)
           - ALTER INDEX ALL ON ... REBUILD
           - Recreate logins / SQL Agent jobs manually
           - Run application smoke tests
```

### AWS Backup Policy (Non-Prod)

| Environment | Backup Window | Retention | Cross-Region | PITR |
|---|---|---|---|---|
| DEV | 03:00 UTC daily | 7 days | No | No |
| QA | 03:00 UTC daily | 14 days | No | No |
| INT/UAT | 02:00 UTC daily | 30 days | No | Yes (7 days) |

All non-prod backups are stored in a dedicated `gga-nonprod-backup-vault` encrypted with the `nonprod-rds-key` KMS CMK.

---

## 6. Full Load + CDC — Production Migration

Production uses AWS DMS Full Load followed by continuous CDC to achieve minimal application downtime. The 11.22 TB dataset is migrated in the background; the only downtime is the final write-freeze and endpoint-switch window (120–240 minutes SLA).

### Migration Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 1: PRE-MIGRATION PREPARATION (Terraform Wave 1)                      │
│                                                                             │
│  • Provision all RDS, DMS, VPC, IAM, KMS via Terraform                     │
│  • Run AWS SCT → generate compatibility report                              │
│  • Remediate ~2% of objects requiring manual fix                           │
│  • Enable CDC on source EC2 SQL Server: sp_cdc_enable_db                   │
│  • Validate DMS network connectivity (source EC2 → DMS → target RDS)      │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 2: DMS FULL LOAD  (background — application continues on EC2)        │
│                                                                             │
│  • DMS task type: full-load                                                 │
│  • Parallel threads: 8 per task; BCP bulk copy enabled                     │
│  • Estimated: ~7 hours for 12 TB at 500 MB/s                              │
│  • Monitor: CloudWatch DMS metrics; row count reconciliation per table     │
│  • On completion: task automatically switches to CDC mode                  │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 3: CDC STEADY STATE  (parallel running — validate while syncing)     │
│                                                                             │
│  • DMS continuously replicates INS/UPD/DEL from EC2 → RDS                 │
│  • Replication lag monitored; target < 30 seconds under normal load        │
│  • Extended parallel validation: row counts, checksums, app shadow testing │
│  • Two mock cutovers performed on INT/UAT to rehearse production steps     │
│  • SQL Agent job replacement strategy finalised (Lambda / EventBridge)     │
└─────────────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 4: CUTOVER  (production maintenance window — 120–240 min SLA)        │
│                                                                             │
│  Step 1  Freeze writes — application teams halt write transactions          │
│  Step 2  Monitor DMS lag until = 0 (all changes applied to RDS)            │
│  Step 3  Stop DMS task gracefully; record final task status                │
│  Step 4  Final row-count validation across all 15 databases                │
│  Step 5  Update connection strings / Route 53 CNAME → RDS endpoint        │
│  Step 6  Execute smoke tests; GGA application team validates               │
│  Step 7  AWS architect sign-off; production traffic live on RDS            │
│  Step 8  72-hr hold: EC2 source retained as rollback point                 │
│  Step 9  DMS instance terminated (cost saving)                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Rollback Plan

If critical issues are found during cutover:
1. Redirect connection strings back to EC2 source (EC2 kept live during hold period).
2. Re-enable SQL Agent jobs and monitoring on source.
3. Revert DNS to original EC2 endpoint.
4. Conduct root-cause analysis; schedule new cutover window.

### Data Validation Checkpoints

| Checkpoint | Method | Pass Criteria |
|---|---|---|
| Row count per table | DMS validation task + manual T-SQL SELECT COUNT(*) | ≤ 0.01% variance |
| Schema object count | sys.objects comparison (source vs target) | 100% match |
| Index integrity | DBCC CHECKDB on target | No errors |
| Application smoke test | GGA app team functional validation | All critical paths pass |
| Performance baseline | Compare query plans and P99 latency | No regression > 10% |

---

## 7. CloudWatch Monitoring

### Monitoring Stack Architecture

```
Data Sources                 Aggregation                  Alerting
─────────────────────────────────────────────────────────────────────────
RDS Enhanced Monitoring  ──► CloudWatch Namespace: AWS/RDS
  (1-second OS metrics)
                         ──► CloudWatch Logs:
RDS Performance Insights       /aws/rds/instance/…/error   ──► CloudWatch Alarms
  (query-level wait stats,      /aws/rds/instance/…/agent        │
   top SQL, DB load)            /aws/dms/tasks/…                 ▼
                                                            SNS Topic
DMS Task Metrics         ──► CloudWatch Namespace: AWS/DMS     │
  (lag, rows, errors)                                          ├── PagerDuty
                         ──► CloudTrail (all API events)       ├── Email DL
AWS Backup Events                                              └── Slack #db-alerts
  (job success/failure)   ──► Backup Audit Manager

Rubrik ◄─── AWS Backup Events (centralised backup visibility & compliance)
```

### Key CloudWatch Alarms

| Alarm Name | Metric | Threshold | Action |
|---|---|---|---|
| `rds-cpu-high` | CPUUtilization | > 85% for 5 min | SNS → DBA team |
| `rds-storage-low` | FreeStorageSpace | < 2.6 TB (20%) | SNS + autoscale trigger |
| `rds-iops-high` | ReadIOPS + WriteIOPS | > 90% provisioned | SNS → DBA review |
| `rds-connections-high` | DatabaseConnections | > 900 | SNS → review proxy pool |
| `rds-replica-lag` | ReplicaLag (DR) | > 900 seconds | SNS → investigate CDC |
| `rds-failover-event` | RDS event subscription | Any failover initiated | EventBridge → PagerDuty |
| `dms-task-error` | CDCIncomingChanges / error rate | Any error | EventBridge → Lambda |
| `dms-cdc-lag` | CDCLatency | > 60 seconds | SNS → DBA team |
| `backup-job-failure` | AWS Backup events | Any FAILED status | SNS + Rubrik alert |
| `rds-deadlock` | Deadlocks (Extended Events) | > 10/min | SNS → DBA review |

### Performance Insights Dashboard

Performance Insights is enabled on all environments with a 7-day retention for non-prod and 731 days (2 years) for production. Key views:

- **DB Load by Wait Type** — identifies whether bottleneck is CPU, I/O, lock, or network.
- **Top SQL by Average Active Sessions** — surfaces highest-impact queries.
- **Counter Metrics** — correlated view of OS metrics alongside query load.

### EventBridge Rules

| Rule | Source Event | Target | Purpose |
|---|---|---|---|
| `rds-failover-notify` | `aws.rds` / `RDS-EVENT-0006` | SNS → PagerDuty | Production failover alert |
| `dms-task-failed` | `aws.dms` / task state = Failed | SNS + Lambda log | Migration task failure |
| `backup-failed-notify` | `aws.backup` / BACKUP_JOB_FAILED | SNS | Backup policy breach |
| `rds-maintenance-notify` | `aws.rds` / maintenance events | SNS → email DL | Advance notice of RDS maintenance |

---

## 8. Security & IAM Boundaries

### Encryption

| Layer | Mechanism | Key |
|---|---|---|
| RDS at rest | AES-256 via AWS KMS CMK | `prod-rds-key` / `nonprod-rds-key` |
| RDS backups | Inherits RDS encryption | Same CMK |
| RDS in transit | TLS 1.2+ enforced (`rds.force_ssl = 1`) | ACM-managed cert |
| S3 (DMS logs, backups) | SSE-KMS | `prod-s3-key` |
| Secrets Manager | Envelope encryption | `prod-secrets-key` |
| Cross-region snapshots | Re-encrypted with DR region CMK | `dr-rds-key` (us-east-1) |

### IAM Roles

| Role | Service Principal | Key Permissions |
|---|---|---|
| `rds-enhanced-monitoring-role` | `monitoring.rds.amazonaws.com` | CloudWatch:PutMetricData |
| `dms-vpc-role` | `dms.amazonaws.com` | VPC describe, ENI management |
| `rds-s3-integration-role` | `rds.amazonaws.com` | S3:GetObject, S3:PutObject (backup bucket) |
| `aws-backup-role` | `backup.amazonaws.com` | RDS snapshot create/copy, KMS:GenerateDataKey |
| `terraform-deploy-role` | CI/CD OIDC | Scoped: RDS, DMS, VPC, KMS, IAM (no *Admin) |
| `dba-admin-role` | IAM Identity Center (SSO) | RDS Connect, Performance Insights read, CW read |

---

## 9. Component Reference

| Component | AWS Service | Environment | Notes |
|---|---|---|---|
| RDS SQL Server 2022 Primary | Amazon RDS | Prod | db.r6i.16xlarge, Multi-AZ |
| RDS SQL Server 2022 Standby | Amazon RDS (managed) | Prod | Multi-AZ sync replica |
| RDS Proxy | Amazon RDS Proxy | Prod | ×3 instances, IAM auth |
| RDS SQL Server 2022 DR | Amazon RDS | DR (us-east-1) | Warm standby |
| RDS DEV | Amazon RDS | Non-Prod | db.r5.4xlarge, single AZ |
| RDS QA | Amazon RDS | Non-Prod | db.r5.4xlarge, single AZ |
| RDS INT/UAT | Amazon RDS | Non-Prod | db.r6i.8xlarge, Multi-AZ |
| DMS Prod Instance | AWS DMS | Migration | r5.4xlarge, full-load + CDC |
| DMS Non-Prod Instance | AWS DMS | Migration | r5.2xlarge, full-load only |
| AWS SCT | AWS SCT | Migration | Schema conversion & report |
| AWS Backup | AWS Backup | All | Policy-driven, vault lock |
| Rubrik | 3rd-party | All | Visibility & compliance |
| KMS CMK (prod) | AWS KMS | Prod | prod-rds-key |
| KMS CMK (non-prod) | AWS KMS | Non-Prod | nonprod-rds-key |
| KMS CMK (DR) | AWS KMS | DR | dr-rds-key (us-east-1) |
| Secrets Manager | AWS Secrets Manager | All | RDS credentials |
| CloudWatch | Amazon CloudWatch | All | Metrics, logs, alarms |
| Performance Insights | RDS Performance Insights | All | Query-level analysis |
| Enhanced Monitoring | RDS Enhanced Monitoring | All | 1-second OS metrics |
| CloudTrail | AWS CloudTrail | All | API audit |
| EventBridge | Amazon EventBridge | All | Event-driven automation |
| SNS | Amazon SNS | All | Alert fan-out |
| S3 | Amazon S3 | All | DMS logs, backups, staging |
| Route 53 | Amazon Route 53 | Prod + DR | DNS failover |
| VPC / Subnets / SGs | Amazon VPC | All | Network isolation |
| Terraform | HashiCorp Terraform | All | IaC for all above |

---

*Document version: 1.0 | Generated from RFP Detailed Solution (Nagarro) | March 2026*
