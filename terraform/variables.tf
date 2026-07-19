# ── Proxmox connection ────────────────────────────────────────────────────────

variable "vault_address" {
  description = "The address of the Vault server"
  type        = string
  default     = "http://100.122.83.102:8200"
}

variable "personal_website_dir" {
  description = "Path to the local clone of the personal-website repository"
  type        = string
  default     = "/home/user/dev/user/personal-website"
}

variable "proxmox_endpoint" {
  description = "Proxmox API URL, e.g. https://192.168.11.10:8006/"
  type        = string
}

variable "proxmox_insecure" {
  description = "Skip TLS certificate verification (set false if using a valid cert)"
  type        = bool
  default     = true
}

variable "proxmox_ssh_user" {
  description = "SSH username on the Proxmox host (needed for some bpg/proxmox operations)"
  type        = string
  default     = "root"
}

variable "proxmox_host" {
  description = "Proxmox host IP or hostname (used for SSH provisioners)"
  type        = string
}

# ── Node / infra defaults ─────────────────────────────────────────────────────

variable "proxmox_node" {
  description = "Proxmox node name (shown in the web UI)"
  type        = string
  default     = "prox"
}

variable "default_storage" {
  description = "Storage pool for container disks"
  type        = string
  default     = "local-lvm"
}

variable "template_storage" {
  description = "Storage pool for CT templates (must be directory-based, usually 'local')"
  type        = string
  default     = "local"
}

variable "default_bridge" {
  description = "Default Linux bridge for container networking"
  type        = string
  default     = "vmbr0"
}

variable "default_gateway" {
  description = "Default IPv4 gateway for containers"
  type        = string
}

# ── SSH access ────────────────────────────────────────────────────────────────

# ── Tailscale ─────────────────────────────────────────────────────────────────

# ── TLS / Cloudflare ──────────────────────────────────────────────────────────

variable "domain" {
  description = "Primary domain for TLS certs and public DNS records (e.g. example.com)"
  type        = string
  default     = "example.com"
}

# ── Alertmanager ──────────────────────────────────────────────────────────────

# ── Wazuh Webhooks ────────────────────────────────────────────────────────────

# ── Authelia SSO ──────────────────────────────────────────────────────────────

variable "proxmox_ssh_private_key_path" {
  description = "Path to the Proxmox SSH private key"
  type        = string
  default     = "/home/user/.ssh/id_temp_proxmox"
}
