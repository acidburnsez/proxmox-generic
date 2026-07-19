# ── K3s Kubernetes Cluster VMs ────────────────────────────────────────────────
#
# Topology:
# Master Node: VM 700 | IP: 192.168.11.90/24
# Worker Node 1: VM 701 | IP: 192.168.11.91/24
# Worker Node 2: VM 702 | IP: 192.168.11.92/24
#

# ── Cloud-Init Debian Image ───────────────────────────────────────────────────

resource "proxmox_download_file" "debian_12_cloud_image" {
  content_type = "iso"
  datastore_id = var.template_storage
  node_name    = var.proxmox_node
  url          = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  file_name    = "debian-12-genericcloud-amd64.img"
}

# ── Master Node ───────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "k3s_master" {
  name        = "k3s-master-01"
  description = "K3s Kubernetes Cluster Control Plane Node"
  tags        = ["terraform", "kubernetes", "k3s-master"]
  node_name   = var.proxmox_node
  vm_id       = 700

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.default_storage
    file_id      = proxmox_download_file.debian_12_cloud_image.id
    interface    = "virtio0"
    size         = 40
  }

  initialization {
    user_data_file_id = "local:snippets/k3s-cloud-config.yaml"
    ip_config {
      ipv4 {
        address = "192.168.11.90/24"
        gateway = var.default_gateway
      }
    }
  }

  serial_device {}

  network_device {
    bridge = var.default_bridge
  }
}

# ── Worker Node 1 ─────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "k3s_worker_1" {
  name        = "k3s-worker-01"
  description = "K3s Kubernetes Worker Node 01"
  tags        = ["terraform", "kubernetes", "k3s-worker"]
  node_name   = var.proxmox_node
  vm_id       = 701

  agent {
    enabled = true
  }

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = var.default_storage
    file_id      = proxmox_download_file.debian_12_cloud_image.id
    interface    = "virtio0"
    size         = 100
  }

  initialization {
    user_data_file_id = "local:snippets/k3s-cloud-config.yaml"
    ip_config {
      ipv4 {
        address = "192.168.11.91/24"
        gateway = var.default_gateway
      }
    }
  }

  serial_device {}

  network_device {
    bridge = var.default_bridge
  }

  lifecycle {
    ignore_changes = [
      hostpci,
    ]
  }
}

# ── Worker Node 2 ─────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_vm" "k3s_worker_2" {
  name        = "k3s-worker-02"
  description = "K3s Kubernetes Worker Node 02"
  tags        = ["terraform", "kubernetes", "k3s-worker"]
  node_name   = var.proxmox_node
  vm_id       = 702

  agent {
    enabled = true
  }

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = var.default_storage
    file_id      = proxmox_download_file.debian_12_cloud_image.id
    interface    = "virtio0"
    size         = 100
  }

  initialization {
    user_data_file_id = "local:snippets/k3s-cloud-config.yaml"
    ip_config {
      ipv4 {
        address = "192.168.11.92/24"
        gateway = var.default_gateway
      }
    }
  }

  serial_device {}

  network_device {
    bridge = var.default_bridge
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "k3s_master_ip" {
  value       = "192.168.11.90"
  description = "K3s Master Control Plane IP"
}

output "k3s_worker_1_ip" {
  value       = "192.168.11.91"
  description = "K3s Worker Node 01 IP"
}

output "k3s_worker_2_ip" {
  value       = "192.168.11.92"
  description = "K3s Worker Node 02 IP"
}
