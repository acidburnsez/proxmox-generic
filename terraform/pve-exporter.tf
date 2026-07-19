# ── Proxmox PVE Exporter ──────────────────────────────────────────────────────
#
# Runs prometheus-pve-exporter in a small LXC, scraping the Proxmox API
# and exposing host/VM/container metrics to Prometheus on port 9221.
#
# Auth reuses the existing proxmox_api_token variable — no extra secrets needed.

locals {
  pve_exporter_vm_id = 302

  # Parse "root@pam!terraform=uuid" into parts for pve.yml config
  _pve_token_parts = split("!", local.proxmox_api_token)
  pve_token_user   = local._pve_token_parts[0]                        # root@pam
  _pve_name_val    = split("=", local._pve_token_parts[1])
  pve_token_name   = local._pve_name_val[0]                           # terraform
  pve_token_value  = local._pve_name_val[1]                           # uuid
}

# ── Container ─────────────────────────────────────────────────────────────────

module "pve_exporter" {
  source = "./modules/lxc"

  vm_id       = local.pve_exporter_vm_id
  hostname    = "pve-exporter"
  description = "Prometheus PVE Exporter — Proxmox host metrics"
  node_name   = var.proxmox_node

  template_file_id = proxmox_download_file.ubuntu_2404_lxc.id

  storage   = var.default_storage
  disk_size = 4
  cpu_cores = 1
  memory_mb = 256

  ip_address = "192.168.11.52/24"
  gateway    = var.default_gateway
  bridge     = var.default_bridge

  ssh_public_key = local.ssh_public_key
  tags           = ["terraform", "monitoring"]
}

# ── Install ───────────────────────────────────────────────────────────────────

resource "null_resource" "pve_exporter_setup" {
  depends_on = [module.pve_exporter]

  triggers = {
    script_hash = filemd5("${path.module}/scripts/install-pve-exporter.sh")
    vm_id       = local.pve_exporter_vm_id
  }

  connection {
    type         = "ssh"
    host         = "192.168.11.52"
    user         = "root"
    agent        = true
    bastion_host = var.proxmox_host
    bastion_user = var.proxmox_ssh_user
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install-pve-exporter.sh"
    destination = "/tmp/install-pve-exporter.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-pve-exporter.sh",
      "/tmp/install-pve-exporter.sh '${local.pve_token_user}' '${local.pve_token_name}' '${local.pve_token_value}'",
    ]
  }
}


# ── Output ────────────────────────────────────────────────────────────────────

output "pve_exporter_ip" {
  value       = module.pve_exporter.ip_address
  description = "PVE exporter metrics: http://<ip>:9221/pve?target=<proxmox_host>"
}
