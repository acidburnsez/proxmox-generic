# Downloads the Ubuntu 24.04 LXC template from Proxmox's official image server.
# Stored on 'local' storage (must be directory-based, not LVM).
# This only runs once — Terraform won't re-download if the file already exists.

resource "proxmox_download_file" "ubuntu_2404_lxc" {
  content_type = "vztmpl"
  datastore_id = var.template_storage
  node_name    = var.proxmox_node

  url = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"

  # Optional: pin to a specific checksum for reproducibility
  # checksum           = "..."
  # checksum_algorithm = "sha256"
}
