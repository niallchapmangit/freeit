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
  }

  # Partial backend — completed at init time with -backend-config flags.
  # Key is injected per-company so each company has isolated state.
  # See infra/README.md for the exact init command.
  backend "s3" {
    use_lockfile = true # Native S3 locking — no DynamoDB required (OpenTofu >= 1.10)
  }

  # Client-side state encryption (OpenTofu >= 1.7, GA in 1.10).
  # TF_VAR_state_passphrase must be set in the environment — never commit it.
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
  region = var.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ── Cloud-init user-data ──────────────────────────────────────────────────────

module "node_bootstrap" {
  source = "../../modules/node-bootstrap"

  company_id  = var.company_id
  k3s_version = var.k3s_version
}

# ── Compute substrate ─────────────────────────────────────────────────────────
# To add a new provider: add a new substrate-<cloud> module call here, gate it
# on var.substrate, and coalesce the node output below.

module "substrate_aws" {
  source = "../../modules/substrate-aws"
  count  = var.substrate == "aws" ? 1 : 0

  company_id     = var.company_id
  node_size      = var.node_size
  ssh_public_key = var.ssh_public_key
  ssh_cidrs      = var.ssh_cidrs
  api_cidrs      = var.api_cidrs
  public_ports   = var.public_ports
  cloud_init     = module.node_bootstrap.cloud_init
  region         = var.region
  tags           = var.tags
}

# Normalize the node output regardless of which substrate was selected.
locals {
  node = coalesce(
    one(module.substrate_aws[*].node),
    # future: one(module.substrate_hetzner[*].node),
  )
}

# ── DNS (Cloudflare) ──────────────────────────────────────────────────────────
# Decoupled from the compute substrate — Cloudflare is always the DNS provider.
# Creates *.{company_id}.free-it-infra.com and {company_id}.free-it-infra.com → node EIP.

module "dns" {
  source = "../../modules/dns-cloudflare"

  company_id         = var.company_id
  root_domain        = var.root_domain
  node_ip            = local.node.public_ip
  cloudflare_zone_id = var.cloudflare_zone_id
}
