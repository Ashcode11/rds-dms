# SCT Assessment & Schema Migration Runbook
## AWS Schema Conversion Tool — EC2 Windows Server 2022
**Tool:** AWS SCT (installed on EC2 Windows Server 2022, same VPC as RDS & DMS)
**Purpose:** Assess compatibility, convert schema, apply DDL to target RDS SQL Server 2022

---

## Prerequisites

| Item | Value |
|---|---|
| SCT Host | EC2 Windows Server 2022 — `<SCT_EC2_PRIVATE_IP>` |
| SCT Version | Latest (download from https://docs.aws.amazon.com/SchemaConversionTool) |
| Source | EC2 SQL Server 2016 — `<SOURCE_EC2_PRIVATE_IP>:1433` |
| Target | RDS SQL Server 2022 — `<RDS_ENDPOINT>:1433` |
| Network | SCT EC2 → Source EC2: TCP 1433 allowed in SG |
|         | SCT EC2 → RDS: TCP 1433 allowed in `rds-sg` from `sct-sg` |
| SCT DB User (Source) | `<SCT_SOURCE_USERNAME>` — needs db_datareader + VIEW DEFINITION |
| SCT DB User (Target) | `<SCT_TARGET_USERNAME>` — needs db_owner on target DB |

---

## Step 1 — Install & Configure SCT

1. RDP into the SCT EC2 instance: `<SCT_EC2_PRIVATE_IP>`
2. Download and install the latest AWS SCT from AWS console or official docs.
3. Install required JDBC drivers:
   - **Microsoft SQL Server JDBC Driver** (mssql-jdbc-12.x.x.jre11.jar)
   - Place in: `C:\SCT\drivers\`
4. Open SCT → **Settings → Global Settings → Drivers**
   - Set Microsoft SQL Server driver path to `C:\SCT\drivers\mssql-jdbc-12.x.x.jre11.jar`

---

## Step 2 — Create New SCT Project

1. Open SCT → **File → New Project**
2. Fill in:
   - **Project Name:** `GGA-MSSQL-Migration`
   - **Location:** `C:\SCT\Projects\GGA-MSSQL-Migration`
   - **Source Engine:** Microsoft SQL Server
   - **Target Engine:** Amazon RDS for SQL Server

---

## Step 3 — Connect to Source (EC2 SQL Server 2016)

1. In SCT, click **Add Source**
2. Enter connection details:
   ```
   Server Name:  <SOURCE_EC2_PRIVATE_IP>
   Port:         1433
   User Name:    <SCT_SOURCE_USERNAME>
   Password:     <SCT_SOURCE_PASSWORD>
   Database:     <SOURCE_DATABASE_NAME>
   ```
3. Click **Test Connection** → should show "Connection successful"
4. Click **Connect**

---

## Step 4 — Connect to Target (RDS SQL Server 2022)

1. In SCT, click **Add Target**
2. Enter connection details:
   ```
   Server Name:  <RDS_ENDPOINT>.rds.amazonaws.com
   Port:         1433
   User Name:    <SCT_TARGET_USERNAME>
   Password:     <SCT_TARGET_PASSWORD>
   Database:     <TARGET_DATABASE_NAME>
   ```
3. Enable **SSL** checkbox
4. Click **Test Connection** → should show "Connection successful"
5. Click **Connect**

---

## Step 5 — Run Assessment Report

1. In SCT, right-click the **source database** → **Create Report**
2. Wait for scan to complete (5–20 min depending on DB size)
3. Review the report:
   - **Action Items** tab — objects needing manual conversion
   - **Summary** tab — % auto-converted vs manual
   - **Warnings** tab — deprecated features (TEXT, NTEXT, IMAGE types)
4. Export the report:
   - **File → Save Report** → save as `GGA-SCT-Assessment-<DB_NAME>-<DATE>.pdf`
   - Copy to: `01-architecture/` folder for documentation

### Expected Results (based on POC)
| Category | Expected Auto-Conversion Rate |
|---|---|
| Storage objects (tables, indexes) | ~100% |
| Code objects (procs, triggers, views) | ~98% |
| Manual remediation needed | ~2% (system-level procs, Service Broker, CLR) |

---

## Step 6 — Remediate Manual Items

Before applying schema to target, fix all **red/orange** action items:

| Common Issue | Resolution |
|---|---|
| `xp_cmdshell` references | Replace with AWS Lambda or SSM Run Command |
| CLR assemblies | Remove or rewrite as T-SQL / Lambda |
| Service Broker objects | Replace with Amazon SQS |
| Linked Server queries | Refactor to use direct connections or federated queries |
| TEXT / NTEXT / IMAGE columns | Alter to VARCHAR(MAX) / NVARCHAR(MAX) / VARBINARY(MAX) |
| SQL Agent jobs with OS paths | Redesign using AWS native scheduling (EventBridge + Lambda) |
| `sp_OA*` extended procs | Replace with application-layer logic |

---

## Step 7 — Convert & Apply Schema to Target

1. In SCT, select all objects under source database
2. Right-click → **Convert Schema**
3. Review converted objects in the **Target** pane (right side)
4. For each object with conversion issues, apply manual fix in SCT editor
5. Once all objects are green/converted:
   - Right-click target database → **Apply to Database**
   - Confirm prompt → SCT applies all DDL to RDS target
6. Verify in SSMS connected to RDS:
   ```sql
   -- Verify table count matches source
   SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE'

   -- Verify stored procedure count
   SELECT COUNT(*) FROM sys.procedures

   -- Verify index count
   SELECT COUNT(*) FROM sys.indexes WHERE index_id > 0
   ```

---

## Step 8 — Post-Schema Validation Checklist

- [ ] All tables created with correct columns and data types
- [ ] Primary keys and unique constraints present
- [ ] Foreign keys applied (or noted if deferred until after DMS load)
- [ ] Indexes created (non-clustered — recreate after DMS full load for performance)
- [ ] Stored procedures compiled without errors
- [ ] Views created successfully
- [ ] Triggers present and enabled
- [ ] Compatibility level set: `ALTER DATABASE [<DB>] SET COMPATIBILITY_LEVEL = 160`
- [ ] SCT assessment report saved to `01-architecture/`
- [ ] Manual remediation items logged in RAID log

---

## Step 9 — Hand Off to DMS

Once schema is applied to target RDS:
1. Note the RDS endpoint: `<RDS_ENDPOINT>.rds.amazonaws.com`
2. Confirm DMS target endpoint is pointing to same DB
3. Start DMS replication task — DMS will begin **full-load** (data only, schema already present)
4. Set DMS task → `TargetTablePrepMode = "TRUNCATE_BEFORE_LOAD"` (not DROP_AND_CREATE, since SCT already created tables)

---

## Rollback

If SCT schema application fails or causes issues:
1. Drop the target database: `DROP DATABASE [<TARGET_DB_NAME>]`
2. Re-create a fresh empty database
3. Fix SCT issues and re-run from Step 7
4. Source EC2 is unaffected throughout (SCT is read-only on source)

---

*Runbook version: 1.0 | March 2026 | GGA MSSQL Migration*
