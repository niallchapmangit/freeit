output "wildcard_fqdn" {
  description = "The wildcard DNS name created (e.g. *.acme-demo.yourdemo.com)."
  value       = "*.${var.company_id}.${var.root_domain}"
}

output "company_domain" {
  description = "The company's base domain (e.g. acme-demo.yourdemo.com). Used by ingress rules and Helm values."
  value       = "${var.company_id}.${var.root_domain}"
}
