# Production Migration — DMS Full Load + CDC Runbook
## EC2 SQL Server 2016 → RDS SQL Server 2022 (Production)

---

## Overview
Production uses AWS DMS Full Load followed by CDC to achieve minimal downtime.
SCT must complete schema creation on target before DMS task is started.

**SLA:** Max production downtime = 120–240 minutes (write freeze to RDS live)

---

## Prerequisites Checklist

- [ ] SCT schema applied to all 15 target databases (see `07-runbooks/sct-assessment-runbook.md`)
- [ ] Terraform prod environment applied (`02-terraform/environments/prod/`)
- [ ] DMS replication instance status = `available`
- [ ] Source and target endpoints tested: **green** in DMS console
- [ ] CDC enabled on all source databases:
  ```sql
  -- Run on each source database on EC2
  EXEC sys.sp_cdc_enable_db;
  -- Verify
  SELECT name, is_cdc_enabled FROM sys.databases WHERE is_cdc_enabled = 1;
  ```
- [ ] Transaction log retention >= 24 hours on source:
  ```sql
  EXEC sp_configure 'Agent XPs', 1; RECONFIGURE;
  ```
- [ ] Two mock cutovers completed on INT/UAT
- [ ] Application team change freeze confirmed for cutover window
- [ ] Rollback plan reviewed and signed off

---

## Phase 1 — Full Load

### 1.1 Update DMS Task for Full Load Phase
Since SCT already created the schema, set task to TRUNCATE (not DROP):

In DMS console → Task → **Modify**:
- `TargetTablePrepMode` = `TRUNCATE_BEFORE_LOAD`

Or update via Terraform `replication_task_settings` in `modules/dms/main.tf`:
```json
"TargetTablePrepMode": "TRUNCATE_BEFORE_LOAD"
```

### 1.2 Start DMS Full Load Task
```bash
# Start task via AWS CLI
aws dms start-replication-task \
  --replication-task-arn <DMS_TASK_ARN> \
  --start-replication-task-type start-replication \
  --region <AWS_REGION>
```

### 1.3 Monitor Full Load Progress
```bash
# Check task status
aws dms describe-replication-tasks \
  --filters Name=replication-task-arn,Values=<DMS_TASK_ARN> \
  --query 'ReplicationTasks[0].{Status:Status,Progress:ReplicationTaskStats}' \
  --region <AWS_REGION>
```

Monitor in CloudWatch:
- `CDCLatency` — should be 0 during full load
- `FullLoadRowsInserted` — should be increasing
- Alert if stalled > 10 minutes

---

## Phase 2 — CDC Steady State

After full load completes, DMS automatically switches to CDC mode.

### 2.1 Confirm CDC is Running
```bash
aws dms describe-replication-tasks \
  --filters Name=replication-task-arn,Values=<DMS_TASK_ARN> \
  --query 'ReplicationTasks[0].Status' \
  --region <AWS_REGION>
# Expected: "running"
```

### 2.2 Monitor CDC Lag
```bash
# Check replication lag via CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/DMS \
  --metric-name CDCLatencySource \
  --dimensions Name=ReplicationInstanceIdentifier,Value=gga-prod-dms-ri \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Average \
  --region <AWS_REGION>
```

**Target:** CDC lag < 30 seconds before proceeding to cutover.

### 2.3 Run Parallel Validation (while CDC is running)
```sql
-- Connect to RDS target and compare row counts with source
-- Source (EC2):
SELECT 'source' AS env, COUNT(*) AS row_count FROM [<DB_NAME>].[dbo].[<TABLE_NAME>]

-- Target (RDS):
SELECT 'target' AS env, COUNT(*) AS row_count FROM [<DB_NAME>].[dbo].[<TABLE_NAME>]
```

---

## Phase 3 — Cutover

**Execute only during approved maintenance window.**

### Step 1 — Freeze Application Writes
- Application team disables write access / puts app in maintenance mode
- Record timestamp: `CUTOVER_START = $(date -u)`

### Step 2 — Wait for CDC Lag = 0
```bash
# Poll until lag = 0
watch -n 10 "aws dms describe-replication-tasks \
  --filters Name=replication-task-arn,Values=<DMS_TASK_ARN> \
  --query 'ReplicationTasks[0].ReplicationTaskStats.CDCLatencySource'"
```

### Step 3 — Stop DMS Task
```bash
aws dms stop-replication-task \
  --replication-task-arn <DMS_TASK_ARN> \
  --region <AWS_REGION>
```

### Step 4 — Final Row Count Validation
```sql
-- Run on all 15 databases — compare source vs target row counts
SELECT
  t.name AS table_name,
  SUM(p.rows) AS row_count
FROM sys.tables t
JOIN sys.partitions p ON t.object_id = p.object_id
WHERE p.index_id IN (0, 1)
GROUP BY t.name
ORDER BY row_count DESC;
```

### Step 5 — Update Application Connection Strings
- Update DNS / Route 53 CNAME or application config to point to:
  `<RDS_ENDPOINT>.rds.amazonaws.com:1433`
- Coordinate with application team for config deployment

### Step 6 — Smoke Test
- [ ] Application login successful
- [ ] Read query returns expected data
- [ ] Write transaction commits successfully
- [ ] Critical business workflows validated
- [ ] Performance acceptable (no obvious query regressions)

### Step 7 — Sign-Off
- [ ] GGA application team sign-off
- [ ] DBA sign-off
- [ ] AWS architect sign-off
- Record timestamp: `CUTOVER_END = $(date -u)`
- Record actual downtime: `CUTOVER_END - CUTOVER_START`

---

## Post-Cutover (72-Hour Hold)

- Keep source EC2 instance running (read-only) for 72 hours as rollback point
- Monitor RDS performance via Performance Insights and CloudWatch dashboards
- After 72 hours with no issues:
  - Terminate DMS replication instance (cost saving)
  - Schedule EC2 source decommission
  - Update documentation with final RDS endpoint

---

## Rollback Procedure

If critical issues are found during or after cutover:

1. Redirect application connection strings back to source EC2
2. Re-enable SQL Agent jobs on source EC2
3. Revert DNS to original EC2 endpoint
4. Record issue in RAID log
5. DMS CDC can be restarted from last checkpoint if needed
6. Schedule new cutover window after root-cause analysis

---

*Runbook version: 1.0 | March 2026 | GGA MSSQL Migration*
