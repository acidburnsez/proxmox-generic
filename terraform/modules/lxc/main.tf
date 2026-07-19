terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_container" "this" {
  vm_id       = var.vm_id
  node_name   = var.node_name
  description = var.description
  tags        = var.tags

  unprivileged  = var.unprivileged
  started       = true
  start_on_boot = var.start_on_boot

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    user_account {
      keys = [var.ssh_public_key]
    }
  }

  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory_mb
    swap      = var.swap_mb
  }

  disk {
    datastore_id = var.storage
    size         = var.disk_size
  }

  network_interface {
    name    = "eth0"
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }

  dynamic "features" {
    for_each = var.nesting || var.unprivileged == false ? [1] : []
    content {
      nesting = var.nesting
    }
  }

  lifecycle {
    ignore_changes = [
      mount_point,
      initialization[0].user_account,
    ]
  }
}
