terraform {
  required_version = ">= 1.10"
}

output "cloud_init" {
  description = "Rendered cloud-init user-data. Pass to substrate-<cloud> as cloud_init."
  value = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    company_id     = var.company_id
    k3s_version    = var.k3s_version
    extra_packages = var.extra_packages
  })
  sensitive = false
}
