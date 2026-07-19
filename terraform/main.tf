terraform {
  required_version = ">= 1.5"

  backend "http" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10"
    }
  }
}

provider "vault" {
  address          = var.vault_address
  skip_child_token = true
}

data "vault_generic_secret" "proxmox_secrets" {
  path = "secret/proxmox"
}

locals {
  secrets = data.vault_generic_secret.proxmox_secrets.data

  proxmox_api_token            = local.secrets["proxmox_api_token"]
  tailscale_auth_key           = local.secrets["tailscale_auth_key"]
  ssh_public_key               = local.secrets["ssh_public_key"]
  cloudflare_api_token         = local.secrets["cloudflare_api_token"]
  alertmanager_discord_webhook = local.secrets["alertmanager_discord_webhook"]
  wazuh_alerts_webhook         = local.secrets["wazuh_alerts_webhook"]
  wazuh_summary_webhook        = local.secrets["wazuh_summary_webhook"]
  authelia_admin_password      = local.secrets["authelia_admin_password"]
  wazuh_gotify_token           = "ArvFsf.E4qKhq8m"
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = local.proxmox_api_token
  insecure  = var.proxmox_insecure

  ssh {
    agent       = false
    username    = var.proxmox_ssh_user
    private_key = file(var.proxmox_ssh_private_key_path)
  }
}
