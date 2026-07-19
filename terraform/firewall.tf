# ── Proxmox Container Firewall ────────────────────────────────────────────────
#
# Isolates each container to only the traffic it legitimately needs.
# Limits lateral movement if any container is compromised.
#
# Policy per container:
#   input_policy  = DROP  (deny all inbound unless explicitly allowed)
#   output_policy = ACCEPT (allow all outbound unless explicitly blocked)
#
# Outbound LAN blocks use ordered rules — specific ACCEPTs before the REJECT.
# Internet traffic is always allowed (falls through to default ACCEPT).
#
# IRC firewall is in irc.tf.
# Tailscale is excluded — it's a subnet router and needs full LAN access.
#
# PREREQUISITE: Proxmox cluster firewall must be enabled once in the web UI:
#   Datacenter → Firewall → Options → Firewall: Yes

# ── Cluster firewall (must be on for container rules to take effect) ──────────

resource "proxmox_virtual_environment_cluster_firewall" "this" {
  enabled = true
}

# Prometheus and Grafana firewall rules have been removed as they are now running in K3s.

# ── PVE Exporter (vm 302) ─────────────────────────────────────────────────────
#
# Only needs inbound from Prometheus and outbound to Proxmox API.

resource "proxmox_virtual_environment_firewall_rules" "pve_exporter" {
  depends_on = [module.pve_exporter, proxmox_virtual_environment_cluster_firewall.this]

  node_name = var.proxmox_node
  vm_id     = module.pve_exporter.id

  # ── Inbound ──────────────────────────────────────────────────────────────────

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = "192.168.11.0/24"
    comment = "SSH from LAN"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "9221"
    source  = "192.168.11.50/32"
    comment = "PVE metrics (Prometheus only)"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "9100"
    source  = "192.168.11.50/32"
    comment = "node_exporter (Prometheus only)"
    enabled = true
  }

  # ── Outbound ─────────────────────────────────────────────────────────────────

  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.11.1/32"
    comment = "Gateway (routing + DNS)"
    enabled = true
  }

  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.11.110/32"
    comment = "Proxmox API (pve-exporter needs this)"
    enabled = true
  }

  rule {
    type    = "out"
    action  = "REJECT"
    dest    = "192.168.11.0/24"
    comment = "Block rest of LAN"
    enabled = true
  }
}

resource "proxmox_virtual_environment_firewall_options" "pve_exporter" {
  depends_on = [proxmox_virtual_environment_firewall_rules.pve_exporter]

  node_name = var.proxmox_node
  vm_id     = module.pve_exporter.id

  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
  log_level_in  = "nolog"
  log_level_out = "nolog"
}

# ── Caddy (vm 303) ────────────────────────────────────────────────────────────
#
# Internet-facing proxy. Outbound locked to only the backends it proxies.

resource "proxmox_virtual_environment_firewall_rules" "caddy" {
  depends_on = [module.caddy, proxmox_virtual_environment_cluster_firewall.this]

  node_name = var.proxmox_node
  vm_id     = module.caddy.id

  # ── Inbound ──────────────────────────────────────────────────────────────────

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = "192.168.11.0/24"
    comment = "SSH from LAN"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "80"
    comment = "HTTP (redirect to HTTPS)"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "443"
    comment = "HTTPS"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "9100"
    source  = "192.168.11.50/32"
    comment = "node_exporter (Prometheus only)"
    enabled = true
  }

  # ── Outbound — only the backends Caddy proxies ────────────────────────────

  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.11.1/32"
    comment = "Gateway (routing + DNS)"
    enabled = true
  }

  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.11.50/32"
    comment = "Prometheus backend"
    enabled = true
  }

  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.11.51/32"
    comment = "Grafana backend"
    enabled = true
  }

  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.11.110/32"
    comment = "Proxmox UI backend"
    enabled = true
  }



  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.11.66/32"
    comment = "Requestrr web UI backend"
    enabled = true
  }

  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.11.57/32"
    comment = "Wazuh dashboard backend"
    enabled = true
  }



  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.11.90/32"
    comment = "K3s Master"
    enabled = true
  }

  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.11.91/32"
    comment = "K3s Worker 1"
    enabled = true
  }

  rule {
    type    = "out"
    action  = "ACCEPT"
    dest    = "192.168.11.92/32"
    comment = "K3s Worker 2"
    enabled = true
  }



  rule {
    type    = "out"
    action  = "REJECT"
    dest    = "192.168.11.0/24"
    comment = "Block rest of LAN"
    enabled = true
  }
}

resource "proxmox_virtual_environment_firewall_options" "caddy" {
  depends_on = [proxmox_virtual_environment_firewall_rules.caddy]

  node_name = var.proxmox_node
  vm_id     = module.caddy.id

  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
  log_level_in  = "nolog"
  log_level_out = "nolog"
}


# Alertmanager and Requestrr firewall rules have been removed as they are now running in K3s.

# ── Wazuh (vm 310) ────────────────────────────────────────────────────────────

resource "proxmox_virtual_environment_firewall_rules" "wazuh" {
  depends_on = [module.wazuh, proxmox_virtual_environment_cluster_firewall.this]

  node_name = var.proxmox_node
  vm_id     = module.wazuh.id

  # ── Inbound ──────────────────────────────────────────────────────────────────

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    source  = "192.168.11.0/24"
    comment = "SSH from LAN"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "443"
    source  = "192.168.11.0/24"
    comment = "Wazuh Dashboard HTTPS"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "1514"
    source  = "192.168.11.0/24"
    comment = "Wazuh Agent Connection (TCP)"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "udp"
    dport   = "1514"
    source  = "192.168.11.0/24"
    comment = "Wazuh Agent Connection (UDP)"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "1515"
    source  = "192.168.11.0/24"
    comment = "Wazuh Agent Enrollment"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "1514"
    source  = "192.168.1.0/24"
    comment = "Wazuh Agent Connection from LAN (TCP)"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "udp"
    dport   = "1514"
    source  = "192.168.1.0/24"
    comment = "Wazuh Agent Connection from LAN (UDP)"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "1515"
    source  = "192.168.1.0/24"
    comment = "Wazuh Agent Enrollment from LAN"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "55000"
    source  = "192.168.11.0/24"
    comment = "Wazuh REST API"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "9100"
    source  = "192.168.11.50/32"
    comment = "node_exporter (Prometheus only)"
    enabled = true
  }

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "udp"
    dport   = "514"
    source  = "192.168.11.1/32"
    comment = "Syslog forwarding from OPNsense"
    enabled = true
  }
}

resource "proxmox_virtual_environment_firewall_options" "wazuh" {
  depends_on = [proxmox_virtual_environment_firewall_rules.wazuh]

  node_name = var.proxmox_node
  vm_id     = module.wazuh.id

  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
  log_level_in  = "nolog"
  log_level_out = "nolog"
}



# ── Homepage (vm 306) ─────────────────────────────────────────────────────────
#
# Dashboard portal. Needs inbound from Caddy/LAN, and outbound to query APIs.




