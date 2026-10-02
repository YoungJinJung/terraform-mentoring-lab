terraform {
  required_version = ">= 1.11.0" # S3 네이티브 잠금(use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
