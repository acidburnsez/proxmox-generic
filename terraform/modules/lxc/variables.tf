variable "vm_id" {
  description = "Unique container ID (100–999999)"
  type        = number
}

variable "hostname" {
  description = "Container hostname"
  type        = string
}

variable "node_name" {
  description = "Proxmox node to deploy on"
  type        = string
}

variable "template_file_id" {
  description = "CT template file ID from proxmox_virtual_environment_download_file"
  type        = string
}

variable "storage" {
  description = "Storage pool for the container root disk"
  type        = string
  default     = "local-lvm"
}

variable "disk_size" {
  description = "Root disk size in GB"
  type        = number
  default     = 8
}

variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 1
}

variable "memory_mb" {
  description = "RAM in MB"
  type        = number
  default     = 512
}

variable "swap_mb" {
  description = "Swap in MB (0 to disable)"
  type        = number
  default     = 512
}

variable "ip_address" {
  description = "Static IPv4 address with prefix, e.g. 192.168.11.50/24"
  type        = string
}

variable "gateway" {
  description = "IPv4 gateway"
  type        = string
}

variable "bridge" {
  description = "Linux bridge to attach to"
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag (null = untagged)"
  type        = number
  default     = null
}

variable "ssh_public_key" {
  description = "SSH public key for root access"
  type        = string
}

variable "tags" {
  description = "List of Proxmox tags"
  type        = list(string)
  default     = ["terraform"]
}

variable "start_on_boot" {
  description = "Auto-start container when Proxmox boots"
  type        = bool
  default     = true
}

variable "nesting" {
  description = "Enable nesting (required for Docker inside LXC)"
  type        = bool
  default     = false
}

variable "unprivileged" {
  description = "Run as unprivileged container (recommended)"
  type        = bool
  default     = true
}

variable "description" {
  description = "Container description shown in the Proxmox UI"
  type        = string
  default     = "Managed by Terraform"
}
