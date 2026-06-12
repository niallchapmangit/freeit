variable "company_id" {
  type        = string
  description = "Company slug — used in hostnames and labels."
}

variable "k3s_version" {
  type        = string
  default     = "v1.30.2+k3s1"
  description = "Pinned k3s version string passed to the install script."
}

variable "extra_packages" {
  type        = list(string)
  default     = []
  description = "Additional apt packages to install during bootstrap."
}
