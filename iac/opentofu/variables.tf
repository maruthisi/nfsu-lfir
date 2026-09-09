variable "linode_token" {
  description = "Linode API token (create in Cloud Manager -> API Tokens)."
  type        = string
  sensitive   = true
}

variable "mgmt_ssh_pubkey" {
  description = "Your personal SSH public key, added to every VM (root + analyst) so you can log in."
  type        = string
}
