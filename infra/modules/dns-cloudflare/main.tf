terraform {
  required_version = ">= 1.10"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

# One wildcard record covers all subdomains for this company:
#   *.acme-demo.free-it-infra.com → node IP
# This means auth.acme-demo.free-it-infra.com, files.acme-demo.free-it-infra.com, etc.
# are all routed to the same node — ingress-nginx routes by hostname from there.
resource "cloudflare_dns_record" "wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*.${var.company_id}.${var.root_domain}"
  type    = "A"
  content = var.node_ip
  ttl     = var.ttl
  proxied = var.proxied
}

# Bare company subdomain — resolves acme-demo.free-it-infra.com itself (e.g. a landing page).
resource "cloudflare_dns_record" "apex" {
  zone_id = var.cloudflare_zone_id
  name    = "${var.company_id}.${var.root_domain}"
  type    = "A"
  content = var.node_ip
  ttl     = var.ttl
  proxied = var.proxied
}
