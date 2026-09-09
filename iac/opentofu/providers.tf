terraform {
  required_version = ">= 1.5"
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "linode" {
  token = var.linode_token

  # Don't watch the Events API to confirm create/delete — that endpoint needs an
  # extra token scope. Skipping it means the token only needs Linodes = Read/Write.
  skip_instance_ready_poll  = true
  skip_instance_delete_poll = true
}
