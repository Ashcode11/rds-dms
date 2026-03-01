terraform {
  backend "s3" {
    bucket         = "<TERRAFORM_STATE_BUCKET>"     # e.g. gga-terraform-state
    key            = "prod/mssql-migration.tfstate"
    region         = "<AWS_REGION>"                 # e.g. us-west-1
    dynamodb_table = "<TERRAFORM_LOCK_TABLE>"       # e.g. gga-terraform-locks
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  required_version = ">= 1.5.0"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "mssql-migration"
      Environment = "prod"
      ManagedBy   = "terraform"
      Owner       = "<TEAM_NAME>"
    }
  }
}

# Secondary provider for DR region
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = {
      Project     = "mssql-migration"
      Environment = "prod-dr"
      ManagedBy   = "terraform"
      Owner       = "<TEAM_NAME>"
    }
  }
}
