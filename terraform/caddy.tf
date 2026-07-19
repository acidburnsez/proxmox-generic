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

resource "null_resource" "caddy_setup" {
  depends_on = [module.caddy]

  triggers = {
    script_hash = filemd5("${path.module}/scripts/install-caddy.sh")
  }

  connection {
    type         = "ssh"
    host         = "192.168.11.53"
    user         = "root"
    agent        = true
    bastion_host = var.proxmox_host
    bastion_user = var.proxmox_ssh_user
  }

  # CF token passed securely
  provisioner "file" {
    content     = "CF_TOKEN='${local.cloudflare_api_token}'"
    destination = "/tmp/.cf_token"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install-caddy.sh"
    destination = "/tmp/install-caddy.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /tmp/.cf_token",
      "chmod +x /tmp/install-caddy.sh",
      "/tmp/install-caddy.sh '${var.domain}'",
      "rm -f /tmp/.cf_token"
    ]
  }
}

output "caddy_ip" {
  value       = module.caddy.ip_address
  description = "Caddy proxy — https://*.example.com"
}
