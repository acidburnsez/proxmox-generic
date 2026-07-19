output "id" {
  description = "Container VM ID"
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "hostname" {
  description = "Container hostname"
  value       = proxmox_virtual_environment_container.this.initialization[0].hostname
}

output "ip_address" {
  description = "Container IP address"
  value       = var.ip_address
}
