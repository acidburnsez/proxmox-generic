# ── Gitea Git Server ─────────────────────────────────────────────────────────
#
# Gitea  → vm_id 309, port 3000
#

module "gitea" {
  source = "./modules/lxc"

  vm_id       = 309
  hostname    = "gitea"
  description = "Gitea Git Server"
  node_name   = var.proxmox_node

  template_file_id = proxmox_download_file.ubuntu_2404_lxc.id

  storage   = var.default_storage
  disk_size = 16
  cpu_cores = 1
  memory_mb = 4096
  nesting   = true # Required for Docker inside LXC

  ip_address = "192.168.11.69/24"
  gateway    = var.default_gateway
  bridge     = var.default_bridge

  ssh_public_key = local.ssh_public_key
  tags           = ["terraform", "services"]
}

resource "null_resource" "gitea_setup" {
  depends_on = [module.gitea]

  triggers = {
    script_hash = filemd5("${path.module}/scripts/install-gitea.sh")
  }

  connection {
    type         = "ssh"
    host         = "192.168.11.69"
    user         = "root"
    agent        = true
    bastion_host = var.proxmox_host
    bastion_user = var.proxmox_ssh_user
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install-gitea.sh"
    destination = "/tmp/install-gitea.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-gitea.sh",
      "/tmp/install-gitea.sh",
    ]
  }
}
