variable "company_id" {
  type        = string
  description = "Unique company slug (e.g. acme-corp). Used in all resource names."

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.company_id))
    error_message = "company_id must be 3-32 lowercase alphanumeric characters or hyphens."
  }
}

variable "substrate" {
  type        = string
  default     = "aws"
  description = "Which cloud substrate to use. Currently only 'aws' is implemented."

  validation {
    condition     = contains(["aws"], var.substrate)
    error_message = "substrate must be 'aws'. Add a new substrate-<cloud> module to extend."
  }
}

variable "node_size" {
  type        = string
  default     = "medium"
  description = "Portable size enum: small | medium | large. medium is the k3s floor."
}

variable "region" {
  type        = string
  default     = "eu-west-1"
  description = "Cloud region. Must be EU for GDPR compliance."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key to install on the node."
}

variable "ssh_cidrs" {
  type        = list(string)
  description = "CIDRs allowed SSH access. Do not use 0.0.0.0/0."
}

variable "api_cidrs" {
  type        = list(string)
  description = "CIDRs allowed k3s API (6443) access. Do not use 0.0.0.0/0."
}

variable "public_ports" {
  type        = list(number)
  default     = [80, 443]
  description = "World-open ports."
}

variable "k3s_version" {
  type        = string
  default     = "v1.30.2+k3s1"
  description = "Pinned k3s version."
}

variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = "Client-side state encryption passphrase. Set via TF_VAR_state_passphrase. Never commit."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags applied to all resources."
}
