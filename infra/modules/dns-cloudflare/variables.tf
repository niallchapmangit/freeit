variable "company_id" {
  type        = string
  description = "Company slug — used as the subdomain label."
}

variable "root_domain" {
  type        = string
  description = "Root demo domain (e.g. free-it-infra.com). Wildcard cert covers *.root_domain."
}

variable "node_ip" {
  type        = string
  description = "Stable public IP of the company node (EIP from substrate-aws)."
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone ID for root_domain. Set via TF_VAR_cloudflare_zone_id."
  sensitive   = true
}

variable "ttl" {
  type        = number
  default     = 1 # 1 = Cloudflare 'Auto' (proxied records ignore TTL)
  description = "DNS TTL in seconds. 1 = Cloudflare Auto."
}

variable "proxied" {
  type        = bool
  default     = false
  description = "Whether to proxy through Cloudflare CDN. False for bare k3s nodes — we terminate TLS at ingress-nginx."
}
