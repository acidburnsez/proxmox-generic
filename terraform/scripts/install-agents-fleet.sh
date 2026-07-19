#!/usr/bin/env bash
# Centralized script to deploy and configure Wazuh Agent on Proxmox Host and all LXCs.
# Runs on the Proxmox host.

set -euo pipefail

MANAGER_IP="192.168.11.57"
AGENT_DEB="/tmp/wazuh-agent_4.8.2.deb"

echo "==> Downloading Wazuh Agent package on host..."
if [ ! -f "$AGENT_DEB" ]; then
  curl -sSL -o "$AGENT_DEB" https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.8.2-1_amd64.deb
fi

# ── 1. Install & Configure on Proxmox Host ────────────────────────────────────
if ! dpkg-query -W -f='${Status}' wazuh-agent 2>/dev/null | grep -q "ok installed"; then
  echo "==> Installing dependencies on Proxmox Host..."
  apt-get update -qq || true
  apt-get install -y -qq lsb-release rsyslog || apt-get install -y lsb-release rsyslog
  echo "==> Installing Wazuh Agent on Proxmox Host..."
  dpkg -i "$AGENT_DEB" || {
    echo "==> Fixing host dependency issues..."
    apt-get install -y -f
    dpkg -i "$AGENT_DEB"
  }
fi

HOST_CONFIG="/var/ossec/etc/ossec.conf"
if [ -f "$HOST_CONFIG" ]; then
  echo "==> Configuring Wazuh Agent on Proxmox Host"
  # Set manager address
  sed -i "s|<address>MANAGER_IP</address>|<address>${MANAGER_IP}</address>|" "$HOST_CONFIG"
  
  # Strip out invalid journald blocks if they exist
  python3 -c "
import re
with open('$HOST_CONFIG', 'r') as f:
    content = f.read()
pattern = r'<localfile>\s*<log_format>journald</log_format>\s*<location>journald</location>\s*</localfile>\s*'
content = re.sub(pattern, '', content, flags=re.DOTALL)
with open('$HOST_CONFIG', 'w') as f:
    f.write(content)
"

  # Inject PVE firewall logs if not already present
  if ! grep -q "/var/log/pve-firewall.log" "$HOST_CONFIG"; then
    echo "Appending /var/log/pve-firewall.log to Host Agent monitor"
    sed -i "s|.*</ossec_config>.*|<localfile>\n    <log_format>syslog</log_format>\n    <location>/var/log/pve-firewall.log</location>\n  </localfile>\n</ossec_config>|" "$HOST_CONFIG"
  fi

  # Inject syslog monitoring if not already present
  if ! grep -q "/var/log/syslog" "$HOST_CONFIG"; then
    echo "Appending /var/log/syslog to Host Agent monitor"
    sed -i "s|.*</ossec_config>.*|<localfile>\n    <log_format>syslog</log_format>\n    <location>/var/log/syslog</location>\n  </localfile>\n</ossec_config>|" "$HOST_CONFIG"
  fi

  # Inject auth.log monitoring if not already present
  if ! grep -q "/var/log/auth.log" "$HOST_CONFIG"; then
    echo "Appending /var/log/auth.log to Host Agent monitor"
    sed -i "s|.*</ossec_config>.*|<localfile>\n    <log_format>syslog</log_format>\n    <location>/var/log/auth.log</location>\n  </localfile>\n</ossec_config>|" "$HOST_CONFIG"
  fi
  
  systemctl daemon-reload
  systemctl enable wazuh-agent
  systemctl restart wazuh-agent
fi

# ── 2. Loop and Rollout to all active LXC containers ──────────────────────────
for vmid in $(pct list | awk 'NR>1 {print $1}'); do
  # Skip the Wazuh Manager container itself (VM 310)
  if [ "$vmid" -eq 310 ]; then
    continue
  fi

  # Skip if container is not running
  if [ "$(pct status "$vmid")" != "status: running" ]; then
    echo "==> Skipping container $vmid (not running)"
    continue
  fi

  echo "==> Deploying Wazuh Agent to Container $vmid..."
  
  # Copy installer to container
  pct push "$vmid" "$AGENT_DEB" "/tmp/wazuh-agent.deb"
  
  # Install agent inside container
  pct exec "$vmid" -- dpkg -i /tmp/wazuh-agent.deb || {
    echo "Warning: failed to install agent on container $vmid, trying apt fallback"
    pct exec "$vmid" -- apt-get update -qq
    pct exec "$vmid" -- apt-get install -y -f
    pct exec "$vmid" -- dpkg -i /tmp/wazuh-agent.deb
  }
  
  # Configure manager endpoint
  pct exec "$vmid" -- sed -i "s|<address>MANAGER_IP</address>|<address>${MANAGER_IP}</address>|" /var/ossec/etc/ossec.conf
  
  # App-specific logs (e.g. Caddy proxy logs for VM 303)
  if [ "$vmid" -eq 303 ]; then
    echo "==> Configuring Caddy and CrowdSec application logs for container 303"
    pct exec "$vmid" -- bash -c '
      CONFIG="/var/ossec/etc/ossec.conf"
      if ! grep -q "/var/log/caddy/access.log" "$CONFIG"; then
        sed -i "s|.*</ossec_config>.*|<localfile>\n    <log_format>json</log_format>\n    <location>/var/log/caddy/access.log</location>\n  </localfile>\n</ossec_config>|" "$CONFIG"
      fi
      if ! grep -q "/var/log/crowdsec.log" "$CONFIG"; then
        sed -i "s|.*</ossec_config>.*|<localfile>\n    <log_format>syslog</log_format>\n    <location>/var/log/crowdsec.log</location>\n  </localfile>\n</ossec_config>|" "$CONFIG"
      fi
    '
  fi
  
  # Start agent service
  pct exec "$vmid" -- systemctl daemon-reload || true
  pct exec "$vmid" -- systemctl enable wazuh-agent || true
  pct exec "$vmid" -- systemctl restart wazuh-agent || true
  
  # Clean up temp installer inside container
  pct exec "$vmid" -- rm -f /tmp/wazuh-agent.deb
  echo "==> Container $vmid Agent setup finished!"
done

echo "==> Fleet rollout of Wazuh Agents completed successfully!"
