# ── Wazuh SIEM / XDR Server ───────────────────────────────────────────────────
#
# All-in-one Wazuh deployment: Indexer, Manager, and Dashboard on a single node.
# VM ID: 310
# IP: 192.168.11.57
# Ports:
#   443   HTTPS Dashboard (reverse proxied via Nginx)
#   1514  Agent connection (TCP/UDP)
#   1515  Agent registration (TCP)
#   55000 API management (TCP)
#
# Dedicated Disk: /dev/sdb formatted as ext4 on the host and bind-mounted as:
#   mp0: /mnt/wazuh/ossec   → /var/ossec
#   mp1: /mnt/wazuh/indexer → /var/lib/wazuh-indexer
#
# Credentials will be saved on first-boot inside the container at:
#   /root/wazuh-passwords.txt
#

locals {
  wazuh_vm_id = 310
}

# ── Host Sysctl Adjustment ───────────────────────────────────────────────────
#
# Wazuh's internal OpenSearch database requires a high vm.max_map_count value
# on the Proxmox host. Because sysctl settings are shared with the host kernel,
# we must apply this configuration on the Proxmox host itself.
resource "null_resource" "host_sysctl_setup" {
  connection {
    type        = "ssh"
    host        = var.proxmox_host
    user        = var.proxmox_ssh_user
    agent       = true
  }

  provisioner "remote-exec" {
    inline = [
      "echo '==> Optimizing host sysctl parameters for Wazuh Indexer'",
      "grep -q 'vm.max_map_count' /etc/sysctl.conf || echo 'vm.max_map_count=262144' >> /etc/sysctl.conf",
      "sysctl -w vm.max_map_count=262144"
    ]
  }
}

# ── Container ─────────────────────────────────────────────────────────────────

module "wazuh" {
  source = "./modules/lxc"

  vm_id       = local.wazuh_vm_id
  hostname    = "wazuh"
  description = "Wazuh SIEM/XDR — centralized security logging and endpoint monitoring"
  node_name   = var.proxmox_node

  template_file_id = proxmox_download_file.ubuntu_2404_lxc.id

  # OpenSearch is memory-intensive; needs at least 2 cores and 4GB RAM
  storage   = var.default_storage
  disk_size = 15 # Small root disk since databases live on /dev/sdb
  cpu_cores = 2
  memory_mb = 4096
  swap_mb   = 0

  ip_address = "192.168.11.57/24"
  gateway    = var.default_gateway
  bridge     = var.default_bridge

  ssh_public_key = local.ssh_public_key
  nesting        = true # Required for OpenSearch process sandboxing
  tags           = ["terraform", "security", "siem"]
}

# ── Dedicated Disk Mount ──────────────────────────────────────────────────────
#
# Mounts /dev/sdb on the Proxmox host, formats it if unformatted, and binds
# subdirectories /var/ossec and /var/lib/wazuh-indexer inside the container.
resource "null_resource" "host_wazuh_mount" {
  depends_on = [module.wazuh]

  connection {
    type        = "ssh"
    host        = var.proxmox_host
    user        = var.proxmox_ssh_user
    agent       = true
  }

  provisioner "remote-exec" {
    inline = [
      "echo '==> Checking and preparing /dev/sdb on the host'",
      # Format /dev/sdb only if it does not contain a filesystem
      "blkid /dev/sdb || mkfs.ext4 -F /dev/sdb",
      # Create host mount directory
      "mkdir -p /mnt/wazuh",
      # Persist mount in fstab
      "grep -q '/mnt/wazuh' /etc/fstab || echo '/dev/sdb /mnt/wazuh ext4 defaults 0 2' >> /etc/fstab",
      "mount -a",
      # Create container subdirectories and set unprivileged permissions
      "mkdir -p /mnt/wazuh/ossec /mnt/wazuh/indexer",
      "chown -R 100000:100000 /mnt/wazuh",
      # Inject mount points into container config
      "CONFIG=/etc/pve/lxc/${local.wazuh_vm_id}.conf",
      "grep -q 'mp0:' $CONFIG || echo 'mp0: /mnt/wazuh/ossec,mp=/var/ossec' >> $CONFIG",
      "grep -q 'mp1:' $CONFIG || echo 'mp1: /mnt/wazuh/indexer,mp=/var/lib/wazuh-indexer' >> $CONFIG",
      # Restart container to apply the mounts
      "pct stop ${local.wazuh_vm_id} && sleep 3 && pct start ${local.wazuh_vm_id}",
      "sleep 10"
    ]
  }
}

# ── Install ───────────────────────────────────────────────────────────────────

resource "null_resource" "wazuh_setup" {
  depends_on = [
    module.wazuh,
    null_resource.host_sysctl_setup,
    null_resource.host_wazuh_mount
  ]

  triggers = {
    script_hash     = filemd5("${path.module}/scripts/install-wazuh.sh")
    summary_hash    = filemd5("${path.module}/scripts/wazuh-summary.py")
    alerts_webhook  = local.wazuh_alerts_webhook
    summary_webhook = local.wazuh_summary_webhook
    gotify_token    = local.wazuh_gotify_token
  }

  # SSH directly to the container via Proxmox host bastion
  connection {
    type         = "ssh"
    host         = "192.168.11.57"
    user         = "root"
    agent        = true
    bastion_host = var.proxmox_host
    bastion_user = var.proxmox_ssh_user
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install-wazuh.sh"
    destination = "/tmp/install-wazuh.sh"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/wazuh-summary.py"
    destination = "/tmp/wazuh-summary.py"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-wazuh.sh",
      "/tmp/install-wazuh.sh '${local.wazuh_alerts_webhook}' '${local.wazuh_gotify_token}'",
      "mkdir -p /var/ossec/scripts",
      "mv -f /tmp/wazuh-summary.py /var/ossec/scripts/wazuh-summary.py",
      "chmod +x /var/ossec/scripts/wazuh-summary.py",
      "echo '0 20 * * * root env SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt /var/ossec/framework/python/bin/python3 /var/ossec/scripts/wazuh-summary.py \"${local.wazuh_summary_webhook}\" > /var/ossec/logs/wazuh-summary.log 2>&1' > /etc/cron.d/wazuh-summary",
      "chmod 644 /etc/cron.d/wazuh-summary",
    ]
  }
}

# ── Agent Fleet Deployment ────────────────────────────────────────────────────
#
# Copies the agent fleet deployment script to the Proxmox host and runs it
# to install and configure the Wazuh Agent on the host and all containers.
resource "null_resource" "wazuh_agent_deploy" {
  depends_on = [
    null_resource.wazuh_setup
  ]

  triggers = {
    script_hash     = filemd5("${path.module}/scripts/install-agents-fleet.sh")
    summary_hash    = filemd5("${path.module}/scripts/wazuh-summary.py")
    summary_webhook = local.wazuh_summary_webhook
  }

  connection {
    type        = "ssh"
    host        = var.proxmox_host
    user        = var.proxmox_ssh_user
    agent       = true
  }

  provisioner "file" {
    source      = "${path.module}/scripts/install-agents-fleet.sh"
    destination = "/tmp/install-agents-fleet.sh"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/wazuh-maintenance.sh"
    destination = "/tmp/wazuh-maintenance"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-agents-fleet.sh",
      "/tmp/install-agents-fleet.sh",
      "rm -f /tmp/install-agents-fleet.sh",
      "echo '#!/bin/bash' > /tmp/wazuh-summary",
      "echo 'pct exec 310 -- env SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt /var/ossec/framework/python/bin/python3 /var/ossec/scripts/wazuh-summary.py \"${local.wazuh_summary_webhook}\"' >> /tmp/wazuh-summary",
      "mv -f /tmp/wazuh-summary /usr/local/bin/wazuh-summary",
      "chmod +x /usr/local/bin/wazuh-summary",
      "mv -f /tmp/wazuh-maintenance /usr/local/bin/wazuh-maintenance",
      "chmod +x /usr/local/bin/wazuh-maintenance"
    ]
  }
}

# ── SSO Integration ───────────────────────────────────────────────────────────

resource "null_resource" "wazuh_sso" {
  depends_on = [null_resource.wazuh_setup]

  triggers = {
    sso_script_hash = filemd5("${path.module}/scripts/configure-wazuh-sso.sh")
  }

  connection {
    type         = "ssh"
    host         = "192.168.11.57"
    user         = "root"
    agent        = true
    bastion_host = var.proxmox_host
    bastion_user = var.proxmox_ssh_user
  }

  provisioner "file" {
    source      = "${path.module}/scripts/configure-wazuh-sso.sh"
    destination = "/tmp/configure-wazuh-sso.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/configure-wazuh-sso.sh",
      "/tmp/configure-wazuh-sso.sh",
      "rm -f /tmp/configure-wazuh-sso.sh"
    ]
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "wazuh_ip" {
  value       = module.wazuh.ip_address
  description = "Wazuh Dashboard IP address"
}
