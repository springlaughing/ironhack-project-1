terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # No backend block: this setup folder keeps its own small state locally.
  # It only creates the bucket that holds the state of everything else.
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project   = "ironhack-project-1"
      Owner     = "evgenia"
      ManagedBy = "terraform"
    }
  }
}