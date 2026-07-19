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

resource "null_resource" "gotify_setup" {
  depends_on = [module.gotify]

  triggers = {
    script_hash = filemd5("${path.module}/scripts/install-gotify.sh")
  }

  connection {
    type         = "ssh"
    host         = "192.168.11.58"
    user         = "root"
    agent        = true
    bastion_host = var.proxmox_host
    bastion_user = var.proxmox_ssh_user
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install-gotify.sh"
    destination = "/tmp/install-gotify.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-gotify.sh",
      "/tmp/install-gotify.sh"
    ]
  }
}

output "gotify_ip" {
  value       = module.gotify.ip_address
  description = "Gotify notification server — http://gotify.example.com"
}
