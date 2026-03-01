# ============================================================
# BACKEND: DR Environment
# Terraform state stored in us-east-1 (DR region)
# ============================================================
# NOTE: Backend configuration is defined inline in main.tf terraform block.
# This file documents the backend settings for reference.
#
# S3 Backend:
#   bucket         = "<TERRAFORM_STATE_BUCKET>"   # S3 bucket in us-east-1
#   key            = "dr/rds/terraform.tfstate"
#   region         = "us-east-1"
#   dynamodb_table = "<TERRAFORM_LOCK_TABLE>"      # DynamoDB table in us-east-1
#   encrypt        = true
#
# Deploy:
#   cd 02-terraform/environments/dr
#   terraform init
#   terraform plan  -var="db_password=<PASSWORD>"
#   terraform apply -var="db_password=<PASSWORD>"
