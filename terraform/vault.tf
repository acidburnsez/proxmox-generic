# ── HashiCorp Vault Server ───────────────────────────────────────────────────
#
# Dedicated Vault instance for secure secrets storage.
# Integrates with Tailscale for zero-secret client token retrieval.
#
# IP: 192.168.11.68
# VM ID: 308
#
# Dispenser API: http://192.168.11.68:8000/token

locals {
  vault_vm_id = 308
}

# ── Container ─────────────────────────────────────────────────────────────────

module "vault" {
  source = "./modules/lxc"

  vm_id       = local.vault_vm_id
  hostname    = "vault"
  description = "HashiCorp Vault Server with Tailscale WhoIs Auth Sidecar"
  node_name   = var.proxmox_node

  template_file_id = proxmox_download_file.ubuntu_2404_lxc.id

  storage   = var.default_storage
  disk_size = 4
  cpu_cores = 1
  memory_mb = 256

  ip_address = "192.168.11.68/24"
  gateway    = var.default_gateway
  bridge     = var.default_bridge

  ssh_public_key = local.ssh_public_key
  tags           = ["terraform", "security"]
}

# ── TUN device passthrough (for Tailscale client) ─────────────────────────────


# ── Install & Provision ────────────────────────────────────────────────────────


# ── Firewall Rules ────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_firewall_options" "vault" {
  depends_on = [module.vault]

  node_name = var.proxmox_node
  vm_id     = local.vault_vm_id

  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
  log_level_in  = "nolog"
  log_level_out = "nolog"
}

resource "proxmox_virtual_environment_firewall_rules" "vault" {
  depends_on = [proxmox_virtual_environment_firewall_options.vault]

  node_name = var.proxmox_node
  vm_id     = local.vault_vm_id

  # Inbound rules
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "udp"
    comment = "Allow Tailscale UDP tunnel traffic"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = "192.168.11.0/24"
    comment = "SSH management from LAN only"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "8200"
    source  = "100.64.0.0/10"
    comment = "Vault API from Tailscale nodes only"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "8000"
    source  = "100.64.0.0/10"
    comment = "Token Dispenser from Tailscale nodes only"
    enabled = true
  }

  # Outbound rules
  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.11.1/32"
    comment = "Allow gateway for DNS & routing"
    enabled = true
  }

  rule {
    type    = "out"
    action  = "REJECT"
    dest    = "192.168.11.0/24"
    comment = "Block outbound to LAN (pivot prevention)"
    enabled = true
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "vault_ip" {
  value       = module.vault.ip_address
  description = "Vault local container IP"
}
