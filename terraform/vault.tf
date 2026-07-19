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

resource "null_resource" "vault_tun" {
  depends_on = [module.vault]

  triggers = {
    vm_id = local.vault_vm_id
  }

  connection {
    type  = "ssh"
    host  = var.proxmox_host
    user  = var.proxmox_ssh_user
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "CONFIG=/etc/pve/lxc/${local.vault_vm_id}.conf",

      "pct stop ${local.vault_vm_id} || true",
      "sleep 3",

      # Allow TUN character device (major 10, minor 200)
      "grep -q 'cgroup2.*10:200' $CONFIG || echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> $CONFIG",

      # Bind-mount /dev/net/tun into the container
      "mkdir -p /dev/net",
      "[ -e /dev/net/tun ] || (mknod /dev/net/tun c 10 200 && chmod 0666 /dev/net/tun)",
      "grep -q 'dev/net/tun' $CONFIG || echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file 0 0' >> $CONFIG",

      "pct start ${local.vault_vm_id}",
      "sleep 10",
    ]
  }
}

# ── Install & Provision ────────────────────────────────────────────────────────

resource "null_resource" "vault_setup" {
  depends_on = [null_resource.vault_tun]

  triggers = {
    script_hash    = filemd5("${path.module}/scripts/install-vault.sh")
    dispenser_hash = filemd5("${path.module}/scripts/vault-token-dispenser.py")
  }

  connection {
    type         = "ssh"
    host         = "192.168.11.68"
    user         = "root"
    agent        = true
    bastion_host = var.proxmox_host
    bastion_user = var.proxmox_ssh_user
  }

  # Copy the installer script
  provisioner "file" {
    source      = "${path.module}/scripts/install-vault.sh"
    destination = "/tmp/install-vault.sh"
  }

  # Copy the Python Token Dispenser
  provisioner "file" {
    source      = "${path.module}/scripts/vault-token-dispenser.py"
    destination = "/tmp/vault-token-dispenser.py"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-vault.sh",
      "/tmp/install-vault.sh '${local.tailscale_auth_key}'",
    ]
  }
}

# ── Firewall Rules ────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_firewall_options" "vault" {
  depends_on = [module.vault]

  node_name = var.proxmox_node
  vm_id     = local.vault_vm_id

  enabled       = false
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
