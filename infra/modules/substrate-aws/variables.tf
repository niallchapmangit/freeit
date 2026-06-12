variable "company_id" {
  type        = string
  description = "Unique company slug. Used in resource names and tags."

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.company_id))
    error_message = "company_id must be 3-32 lowercase alphanumeric characters or hyphens."
  }
}

variable "node_size" {
  type        = string
  default     = "medium"
  description = "Portable size enum: small | medium | large. medium is the k3s floor."

  validation {
    condition     = contains(["small", "medium", "large"], var.node_size)
    error_message = "node_size must be small, medium, or large."
  }
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key material to install on the instance."
}

variable "ssh_cidrs" {
  type        = list(string)
  description = "CIDRs allowed on port 22. Must not include 0.0.0.0/0."

  validation {
    condition     = !contains(var.ssh_cidrs, "0.0.0.0/0")
    error_message = "ssh_cidrs must not contain 0.0.0.0/0."
  }
}

variable "api_cidrs" {
  type        = list(string)
  description = "CIDRs allowed on port 6443 (k3s API). Must not include 0.0.0.0/0."

  validation {
    condition     = !contains(var.api_cidrs, "0.0.0.0/0")
    error_message = "api_cidrs must not contain 0.0.0.0/0 — the k3s API must never be world-open."
  }
}

variable "public_ports" {
  type        = list(number)
  default     = [80, 443]
  description = "World-open ports (HTTP/HTTPS by default)."
}

variable "cloud_init" {
  type        = string
  description = "Rendered cloud-init user-data from the node-bootstrap module."
}

variable "region" {
  type        = string
  default     = "eu-west-1"
  description = "AWS region. Must be an EU region for GDPR compliance."

  validation {
    condition     = can(regex("^eu-", var.region))
    error_message = "region must be an EU region (eu-*) per GDPR requirements."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags applied to all resources."
}
