terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Values come from backend.hcl (created by infra/bootstrap):
  #   terraform init -backend-config=backend.hcl
  # use_lockfile = native S3 state locking, no DynamoDB table needed.
  backend "s3" {
    key          = "dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "github.com/Judewakim/terraform-ecs-platform"
    }
  }
}
