# ============================================================
# MODULE VARIABLES: dms
# ============================================================

variable "identifier" {
  description = "Identifier prefix for all DMS resources (e.g. gga-prod, gga-nonprod)"
  type        = string
}

variable "replication_instance_class" {
  description = "DMS replication instance class. Prod: dms.r5.4xlarge | NonProd: dms.r5.2xlarge"
  type        = string
  # "dms.r5.4xlarge"  → prod    (16 vCPU / 128 GiB, ~500 MB/s)
  # "dms.r5.2xlarge"  → nonprod (8 vCPU / 64 GiB)
}

variable "allocated_storage" {
  description = "Storage allocated to DMS replication instance in GB"
  type        = number
  default     = 500
  # Prod: 500 | NonProd: 100
}

# ---- Network (Existing Resources) ----
variable "subnet_ids" {
  description = "List of EXISTING subnet IDs for the DMS replication subnet group"
  type        = list(string)
  # Example: ["subnet-<ID1>", "subnet-<ID2>"]
}

variable "security_group_ids" {
  description = "List of EXISTING security group IDs to attach to the DMS replication instance"
  type        = list(string)
  # Example: ["sg-<DMS_SG_ID>"]
}

# ---- Migration Type ----
variable "migration_type" {
  description = "DMS migration type"
  type        = string
  default     = "full-load-and-cdc"
  # "full-load"          → nonprod (one-time)
  # "full-load-and-cdc"  → prod (minimal downtime)
}

# ---- Source Endpoint (EC2 SQL Server 2016) ----
variable "source_server_name" {
  description = "Hostname or IP of source EC2 SQL Server 2016 instance"
  type        = string
  # Example: "<SOURCE_EC2_PRIVATE_IP>"
}

variable "source_database_name" {
  description = "Source database name to migrate"
  type        = string
  # Example: "<SOURCE_DB_NAME>"
}

variable "source_username" {
  description = "Username for source SQL Server connection"
  type        = string
  sensitive   = true
  # Example: "<SOURCE_DB_USERNAME>"
}

variable "source_password" {
  description = "Password for source SQL Server connection"
  type        = string
  sensitive   = true
  # Example: "<SOURCE_DB_PASSWORD>"
}

variable "source_schema" {
  description = "Source schema name to include in table mappings"
  type        = string
  default     = "dbo"
}

# ---- Target Endpoint (RDS SQL Server 2022) ----
variable "target_server_name" {
  description = "RDS SQL Server 2022 endpoint address"
  type        = string
  # Example: "<RDS_ENDPOINT>.rds.amazonaws.com"
}

variable "target_database_name" {
  description = "Target database name on RDS"
  type        = string
  # Example: "<TARGET_DB_NAME>"
}

variable "target_username" {
  description = "Username for target RDS connection"
  type        = string
  sensitive   = true
  # Example: "<TARGET_DB_USERNAME>"
}

variable "target_password" {
  description = "Password for target RDS connection"
  type        = string
  sensitive   = true
  # Example: "<TARGET_DB_PASSWORD>"
}

# ---- Tags ----
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
