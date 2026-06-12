terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Bootstrap runs with local state — it IS the thing that creates remote state.
}

variable "state_bucket_name" {
  type        = string
  description = "Globally-unique S3 bucket name for OpenTofu state (e.g. freeit-tofu-state-prod)."
}

variable "aws_region" {
  type        = string
  default     = "eu-west-1"
  description = "EU region. Do not change without an explicit decision (GDPR)."
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket_name
  force_destroy = false

  tags = {
    Project     = "freeit"
    ManagedBy   = "opentofu"
    Environment = "shared"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

output "state_bucket_name" {
  value       = aws_s3_bucket.state.bucket
  description = "Pass this to per-company backend configs."
}

output "state_bucket_region" {
  value       = var.aws_region
  description = "Region for per-company backend configs."
}
