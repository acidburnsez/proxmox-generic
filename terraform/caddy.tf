# ── Caddy Reverse Proxy ───────────────────────────────────────────────────────
#
# TLS-terminating reverse proxy for all personal production services.
# Deploys Caddy in CT 303 (192.168.11.53) replacing Nginx.
# Handles automatic Let's Encrypt wildcard certs via Cloudflare DNS-01.
#

module "caddy" {
  source = "./modules/lxc"

  vm_id       = 303
  hostname    = "caddy"
  description = "Caddy reverse proxy — TLS termination for all personal production services"
  node_name   = var.proxmox_node

  template_file_id = proxmox_download_file.ubuntu_2404_lxc.id

  storage   = var.default_storage
  disk_size = 4
  cpu_cores = 1
  memory_mb = 256

  ip_address = "192.168.11.53/24"
  gateway    = var.default_gateway
  bridge     = var.default_bridge

  ssh_public_key = local.ssh_public_key
  tags           = ["terraform", "proxy"]
}


output "caddy_ip" {
  value       = module.caddy.ip_address
  description = "Caddy proxy — https://*.example.com"
}
