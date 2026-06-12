variable "root_domain" {
  type        = string
  default     = "yourdemo.com"
  description = "Root demo domain. Wildcard cert covers *.root_domain."
}

variable "acme_email" {
  type        = string
  description = "Email for Let's Encrypt account registration and expiry notices."
}

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token with Zone:DNS:Edit for root_domain. Set via TF_VAR_cloudflare_api_token."
}

variable "cloudflare_zone_id" {
  type        = string
  sensitive   = true
  description = "Cloudflare zone ID for root_domain. Set via TF_VAR_cloudflare_zone_id."
}

variable "state_bucket_name" {
  type        = string
  description = "The S3 state bucket (created by bootstrap/). Cert PEM files are stored here."
}

variable "aws_region" {
  type        = string
  default     = "eu-west-1"
  description = "EU AWS region."
}

variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = "Client-side state encryption passphrase. Set via TF_VAR_state_passphrase."
}
