terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State lives in the S3 bucket from terraform/bootstrap (issue #11).
  # The bucket name comes from backend.hcl, which Git ignores:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    bucket       = "voting-app-tfstate-evgenia-686699774218"
    key          = "voting-app/terraform.tfstate" # path of the state file inside the bucket
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # a lock file next to the state stops two runs at once
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "ironhack-project-1"
      Owner     = "evgenia"
      ManagedBy = "terraform"
    }
  }
}