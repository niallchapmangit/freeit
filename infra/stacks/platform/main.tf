terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Platform-level state — shared, not per-company.
  # init: tofu -chdir=infra/stacks/platform init \
  #   -backend-config="bucket=<state_bucket>" \
  #   -backend-config="key=platform/terraform.tfstate" \
  #   -backend-config="region=eu-west-1"
  backend "s3" {
    use_lockfile = true
  }

  encryption {
    key_provider "pbkdf2" "state_key" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "default" {
      keys = key_provider.pbkdf2.state_key
    }
    state {
      method = method.aes_gcm.default
    }
    plan {
      method = method.aes_gcm.default
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ACME (Let's Encrypt) via DNS-01 challenge — Cloudflare fulfils the challenge.
# DNS-01 is required for wildcard certs.
provider "acme" {
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

# ── ACME account key ──────────────────────────────────────────────────────────

resource "tls_private_key" "acme_account" {
  algorithm = "ED25519"
}

resource "acme_registration" "freeit" {
  account_key_pem = tls_private_key.acme_account.private_key_pem
  email_address   = var.acme_email
}

# ── Wildcard TLS certificate ─────────────────────────────────────────────────

resource "acme_certificate" "wildcard" {
  account_key_pem = acme_registration.freeit.account_key_pem

  # *.yourdemo.com covers acme-demo.yourdemo.com, auth.acme-demo.yourdemo.com, etc.
  # The SAN covers the root domain itself too.
  common_name               = "*.${var.root_domain}"
  subject_alternative_names = ["${var.root_domain}"]

  dns_challenge {
    provider = "cloudflare"
    config = {
      CF_DNS_API_TOKEN = var.cloudflare_api_token
    }
  }
}

# ── Store cert in S3 (encrypted at rest) ─────────────────────────────────────
# bootstrap-cluster.sh fetches these at deploy time.

resource "aws_s3_object" "wildcard_cert" {
  bucket  = var.state_bucket_name
  key     = "platform/wildcard-tls/tls.crt"
  content = "${acme_certificate.wildcard.certificate_pem}${acme_certificate.wildcard.issuer_pem}"

  server_side_encryption = "aws:kms"
}

resource "aws_s3_object" "wildcard_key" {
  bucket  = var.state_bucket_name
  key     = "platform/wildcard-tls/tls.key"
  content = acme_certificate.wildcard.private_key_pem

  server_side_encryption = "aws:kms"
}
