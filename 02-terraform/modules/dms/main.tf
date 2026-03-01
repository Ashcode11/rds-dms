# ============================================================
# MODULE: dms
# Provisions DMS replication instance, source/target endpoints,
# and replication task.
# Uses EXISTING VPC subnets and security groups.
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
# DMS Replication Subnet Group — uses existing subnets
# ------------------------------------------------------------
resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = "${var.identifier}-dms-subnet-group"
  replication_subnet_group_description = "DMS subnet group for ${var.identifier}"
  subnet_ids                           = var.subnet_ids   # <EXISTING_SUBNET_IDS>

  tags = merge(var.tags, { Name = "${var.identifier}-dms-subnet-group" })
}

# ------------------------------------------------------------
# DMS Replication Instance
# ------------------------------------------------------------
resource "aws_dms_replication_instance" "this" {
  replication_instance_id    = "${var.identifier}-dms-ri"
  replication_instance_class = var.replication_instance_class  # e.g. dms.r5.4xlarge
  allocated_storage          = var.allocated_storage            # GB (e.g. 500)
  engine_version             = "3.5.3"                          # Latest stable — update as needed

  replication_subnet_group_id    = aws_dms_replication_subnet_group.this.id
  vpc_security_group_ids         = var.security_group_ids       # <EXISTING_DMS_SG_IDS>

  multi_az                       = false   # DMS instance is stateless; single AZ is fine
  publicly_accessible            = false
  auto_minor_version_upgrade     = true
  allow_major_version_upgrade    = false

  tags = merge(var.tags, { Name = "${var.identifier}-dms-ri" })
}

# ------------------------------------------------------------
# Source Endpoint — EC2 SQL Server 2016
# ------------------------------------------------------------
resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${var.identifier}-source"
  endpoint_type = "source"
  engine_name   = "sqlserver"

  server_name   = var.source_server_name    # <SOURCE_EC2_IP_OR_HOSTNAME>
  port          = 1433
  database_name = var.source_database_name  # <SOURCE_DATABASE_NAME>
  username      = var.source_username       # <SOURCE_DB_USERNAME>
  password      = var.source_password       # <SOURCE_DB_PASSWORD>

  ssl_mode = "none"   # Internal VPC traffic — update to "require" if needed

  extra_connection_attributes = join(";", [
    "useBcpFullLoad=Y",
    "parallelLoadThreads=8",
    "BCPPacketSize=32768",
    "queryTimeout=300"
  ])

  tags = merge(var.tags, { Name = "${var.identifier}-source-endpoint" })
}

# ------------------------------------------------------------
# Target Endpoint — RDS SQL Server 2022
# ------------------------------------------------------------
resource "aws_dms_endpoint" "target" {
  endpoint_id   = "${var.identifier}-target"
  endpoint_type = "target"
  engine_name   = "sqlserver"

  server_name   = var.target_server_name    # <RDS_ENDPOINT_ADDRESS>
  port          = 1433
  database_name = var.target_database_name  # <TARGET_DATABASE_NAME>
  username      = var.target_username       # <TARGET_DB_USERNAME>
  password      = var.target_password       # <TARGET_DB_PASSWORD>

  ssl_mode = "require"   # Enforce TLS to RDS

  extra_connection_attributes = join(";", [
    "parallelApplyThreads=8",
    "parallelApplyBufferSize=1000"
  ])

  tags = merge(var.tags, { Name = "${var.identifier}-target-endpoint" })
}

# ------------------------------------------------------------
# Replication Task — Full Load + CDC (prod) or Full Load only (nonprod)
# ------------------------------------------------------------
resource "aws_dms_replication_task" "this" {
  replication_task_id       = "${var.identifier}-task"
  migration_type            = var.migration_type   # "full-load" | "cdc" | "full-load-and-cdc"

  replication_instance_arn  = aws_dms_replication_instance.this.replication_instance_arn
  source_endpoint_arn       = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn       = aws_dms_endpoint.target.endpoint_arn

  table_mappings = jsonencode({
    rules = [
      {
        rule-type = "selection"
        rule-id   = "1"
        rule-name = "include-all-tables"
        object-locator = {
          schema-name = var.source_schema   # <SOURCE_SCHEMA_NAME> e.g. "dbo"
          table-name  = "%"
        }
        rule-action = "include"
      }
    ]
  })

  replication_task_settings = jsonencode({
    TargetMetadata = {
      TargetSchema               = ""
      SupportLobs                = true
      FullLobMode                = false
      LobChunkSize               = 64
      LimitedSizeLobMode         = true
      LobMaxSize                 = 65536
    }
    FullLoadSettings = {
      TargetTablePrepMode        = "DROP_AND_CREATE"
      CreatePkAfterFullLoad      = false
      StopTaskCachedChangesApplied = false
      StopTaskCachedChangesNotApplied = false
      MaxFullLoadSubTasks        = 8
      TransactionConsistencyTimeout = 600
      CommitRate                 = 50000
    }
    Logging = {
      EnableLogging              = true
      LogComponents = [
        { Id = "SOURCE_UNLOAD", Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TARGET_LOAD",   Severity = "LOGGER_SEVERITY_DEFAULT" },
        { Id = "TASK_MANAGER",  Severity = "LOGGER_SEVERITY_DEFAULT" }
      ]
    }
    ControlTablesSettings = {
      historyTimeslotInMinutes   = 5
      StatusTableEnabled         = true
      SuspendedTablesTableEnabled = true
    }
  })

  tags = merge(var.tags, { Name = "${var.identifier}-task" })
}
