# ── Gotify Notification Server ────────────────────────────────────────────────
#
# Unified notification backend for real-time alerts.
# CT ID: 307
# IP: 192.168.11.58
#

module "gotify" {
  source = "./modules/lxc"

  vm_id       = 307
  hostname    = "gotify"
  description = "Gotify notification server — background push notifications for SecOps mobile app"
  node_name   = var.proxmox_node

  template_file_id = proxmox_download_file.ubuntu_2404_lxc.id

  storage   = var.default_storage
  disk_size = 4
  cpu_cores = 1
  memory_mb = 256

  ip_address = "192.168.11.58/24"
  gateway    = var.default_gateway
  bridge     = var.default_bridge

  ssh_public_key = local.ssh_public_key
  tags           = ["terraform", "notifications"]
}


output "gotify_ip" {
  value       = module.gotify.ip_address
  description = "Gotify notification server — http://gotify.example.com"
}
