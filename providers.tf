terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    # Configured at init time via -backend-config flags.
    # See scripts/bootstrap-state-bucket.sh for the bootstrap and
    # the exact `terraform init` command to run.
  }
}

provider "aws" {
  region = var.region
}
