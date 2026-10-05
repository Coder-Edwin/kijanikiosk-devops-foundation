# One-time bootstrap: the S3 bucket that holds the main configuration's state.
#
# This has to exist before the main config can `terraform init`, so it uses
# local state (chicken and egg). Run once per account/region:
#
#   cd terraform/bootstrap
#   terraform init && terraform apply -var aws_region=ap-south-1
#
# It is deliberately NOT destroyed by pipeline.sh destroy: deleting the bucket
# would delete the record of what exists.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  description = "Region for the state bucket. Must match the region pipeline.sh uses."
  type        = string
  default     = "ap-south-1"
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  # Bucket names are global; the account ID and region keep this one unique.
  bucket_name = "kijanikiosk-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  tags = {
    Project   = "kijanikiosk"
    Purpose   = "terraform-state"
    ManagedBy = "terraform-bootstrap"
  }
}

# Every state write is kept, so a bad apply can be rolled back.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# State can contain secrets: encrypt it at rest.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# And never let it become public.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket" {
  description = "Name of the state bucket. pipeline.sh computes the same name."
  value       = aws_s3_bucket.tfstate.bucket
}
