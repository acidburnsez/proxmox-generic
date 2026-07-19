# ── Network configuration ─────────────────────────────────────────────────────
#
# vmbr0 is your existing default bridge (usually created by Proxmox installer).
# Add extra bridges or VLANs here as needed.
#
# Example: a second bridge for an isolated container network.
# Uncomment and adjust to use it.

# resource "proxmox_virtual_environment_network_linux_bridge" "vmbr1" {
#   node_name = var.proxmox_node
#   name      = "vmbr1"
#   comment   = "Isolated container network (Terraform managed)"
#   address   = "10.10.10.1/24"
#   autostart = true
# }

# Example: VLAN interface on top of vmbr0
# resource "proxmox_virtual_environment_network_linux_vlan" "vlan10" {
#   node_name  = var.proxmox_node
#   name       = "vmbr0.10"
#   comment    = "VLAN 10 (Terraform managed)"
#   autostart  = true
# }
