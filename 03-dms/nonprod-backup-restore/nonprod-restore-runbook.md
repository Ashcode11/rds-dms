# NonProd Migration — Native Backup & Restore via S3
## EC2 SQL Server 2016 → RDS SQL Server 2022 (DEV / QA / INT-UAT)

---

## Overview
Non-production environments use native SQL Server `.bak` backup uploaded to S3,
then restored into RDS using the `rds_restore_database` stored procedure.
No DMS CDC is needed — a maintenance window is acceptable for non-prod.

---

## Step 1 — Create S3 Bucket for Backups

```bash
aws s3api create-bucket \
  --bucket <NONPROD_BACKUP_S3_BUCKET> \
  --region <AWS_REGION> \
  --create-bucket-configuration LocationConstraint=<AWS_REGION>

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket <NONPROD_BACKUP_S3_BUCKET> \
  --versioning-configuration Status=Enabled

# Block public access
aws s3api put-public-access-block \
  --bucket <NONPROD_BACKUP_S3_BUCKET> \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

---

## Step 2 — Take Backup on Source EC2 SQL Server 2016

Connect to source EC2 via SSMS or run via sqlcmd:

```sql
-- Full backup with compression
BACKUP DATABASE [<SOURCE_DB_NAME>]
TO DISK = 'D:\Backups\<SOURCE_DB_NAME>_migration.bak'
WITH
  COMPRESSION,
  CHECKSUM,
  STATS = 10,
  FORMAT,
  MEDIANAME = 'Migration',
  NAME = '<SOURCE_DB_NAME> Migration Backup';

-- Verify backup integrity
RESTORE VERIFYONLY
FROM DISK = 'D:\Backups\<SOURCE_DB_NAME>_migration.bak'
WITH CHECKSUM;
```

---

## Step 3 — Upload Backup to S3

Run on the source EC2 (AWS CLI must be installed and configured):

```bash
# Single file upload
aws s3 cp "D:\Backups\<SOURCE_DB_NAME>_migration.bak" \
  s3://<NONPROD_BACKUP_S3_BUCKET>/<ENV>/<SOURCE_DB_NAME>/ \
  --region <AWS_REGION>

# For large files (>5 GB) — use multipart upload
aws s3 cp "D:\Backups\<SOURCE_DB_NAME>_migration.bak" \
  s3://<NONPROD_BACKUP_S3_BUCKET>/<ENV>/<SOURCE_DB_NAME>/ \
  --region <AWS_REGION> \
  --expected-size <FILE_SIZE_BYTES>

# Verify upload
aws s3 ls s3://<NONPROD_BACKUP_S3_BUCKET>/<ENV>/<SOURCE_DB_NAME>/
```

---

## Step 4 — Restore into RDS SQL Server 2022

Connect to target RDS via SSMS (`<RDS_ENDPOINT>:1433`):

```sql
-- Initiate restore from S3
EXEC msdb.dbo.rds_restore_database
  @restore_db_name   = '<TARGET_DB_NAME>',
  @s3_arn_to_restore_from = 'arn:aws:s3:::<NONPROD_BACKUP_S3_BUCKET>/<ENV>/<SOURCE_DB_NAME>/<SOURCE_DB_NAME>_migration.bak';

-- Monitor restore progress
EXEC msdb.dbo.rds_task_status @db_name = '<TARGET_DB_NAME>';
-- Repeat until [lifecycle] = 'SUCCESS'
```

---

## Step 5 — Post-Restore Configuration

```sql
-- Set compatibility level to SQL Server 2022
ALTER DATABASE [<TARGET_DB_NAME>]
SET COMPATIBILITY_LEVEL = 160;

-- Update statistics on all tables
EXEC sp_updatestats;

-- Rebuild all indexes (fragmentation from restore)
EXEC sp_MSforeachtable
  'ALTER INDEX ALL ON ? REBUILD WITH (ONLINE = OFF, SORT_IN_TEMPDB = ON)';

-- Set database to MULTI_USER
ALTER DATABASE [<TARGET_DB_NAME>] SET MULTI_USER;

-- Verify row counts match source
SELECT
  t.name AS TableName,
  p.rows AS RowCount
FROM sys.tables t
JOIN sys.partitions p ON t.object_id = p.object_id
WHERE p.index_id IN (0,1)
ORDER BY p.rows DESC;
```

---

## Step 6 — Validation Checklist

- [ ] Restore status = SUCCESS
- [ ] Row counts match source (manual spot-check on top 10 tables)
- [ ] Application connectivity test — update connection string to RDS endpoint
- [ ] Stored procedure execution test
- [ ] SQL Agent jobs reviewed and recreated/replaced as needed
- [ ] Compatibility level = 160 confirmed
- [ ] Sign-off from application team / DBA

---

*Runbook version: 1.0 | March 2026 | GGA MSSQL Migration*
