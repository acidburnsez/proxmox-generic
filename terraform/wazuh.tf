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

# ── Install ───────────────────────────────────────────────────────────────────


# ── Agent Fleet Deployment ────────────────────────────────────────────────────
#
# Copies the agent fleet deployment script to the Proxmox host and runs it
# to install and configure the Wazuh Agent on the host and all containers.

# ── SSO Integration ───────────────────────────────────────────────────────────


# ── Outputs ───────────────────────────────────────────────────────────────────

output "wazuh_ip" {
  value       = module.wazuh.ip_address
  description = "Wazuh Dashboard IP address"
}
