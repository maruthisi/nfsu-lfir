variable "linode_token" {
  description = "Linode API token (create in Cloud Manager -> API Tokens)."
  type        = string
  sensitive   = true
}

variable "mgmt_ssh_pubkey" {
  description = "Your personal SSH public key, added to every VM (root + analyst) so you can log in."
  type        = string
}

variable "root_password" {
  description = "Known root password set on every VM (for console/Lish/password SSH). Override via TF_VAR_root_password."
  type        = string
  sensitive   = true
  default     = "Nfsu@Lfir2026"
}

variable "analyst_password" {
  description = "Password for the 'analyst' login on mirrors, so students without an SSH key can log in. Override via TF_VAR_analyst_password."
  type        = string
  sensitive   = true
  default     = "Analyst@2026"
}
