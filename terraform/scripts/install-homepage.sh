#!/usr/bin/env bash
# Installs Homepage dashboard.
# Called by Terraform null_resource — do not run manually.

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive

DOMAIN="${1:-example.com}"

echo "==> Installing Docker and dependencies"
apt-get update -qq
apt-get install -y -qq docker.io docker-compose-v2 curl

echo "==> Creating Homepage directories"
mkdir -p /opt/homepage/config

echo "==> Writing docker-compose.yml"
cat > /opt/homepage/docker-compose.yml << EOF
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    ports:
      - 3000:3000
    environment:
      - HOMEPAGE_ALLOWED_HOSTS=homepage.${DOMAIN},192.168.11.70
    volumes:
      - /opt/homepage/config:/app/config
      - /opt/homepage/images:/app/public/images
    restart: unless-stopped
EOF

echo "==> Writing settings.yaml"
cat > /opt/homepage/config/settings.yaml << EOF
title: Personal Production SSO
background: /images/background.jpg
theme: dark
layout:
  Management:
    style: grid
    columns: 4
  Media Stack:
    style: grid
    columns: 4
EOF

echo "==> Writing bookmarks.yaml"
cat > /opt/homepage/config/bookmarks.yaml << EOF
- Infrastructure:
    - Proxmox VE:
        - icon: proxmox
          abbr: PVE
          href: https://proxmox.${DOMAIN}
    - Tailscale:
        - icon: tailscale
          abbr: TS
          href: https://login.tailscale.com
- Communication:
    - Ergo IRC:
        - icon: chat
          abbr: IRC
          href: ircs://irc.${DOMAIN}:6697
EOF

echo "==> Writing services.yaml"
cat > /opt/homepage/config/services.yaml << EOF
- Management:
    - Authelia SSO:
        icon: authelia
        href: https://auth.${DOMAIN}
        description: SSO & MFA Gateway
    - Wazuh SIEM:
        icon: wazuh
        href: https://wazuh.${DOMAIN}
        description: Security Operations
    - Gitea Git Server:
        icon: gitea
        href: https://gitea.${DOMAIN}
        description: Git Code Repositories
    - Grafana:
        icon: grafana
        href: https://grafana.${DOMAIN}
        description: Metrics & Logs
    - Prometheus:
        icon: prometheus
        href: https://prometheus.${DOMAIN}
        description: Scraper Engine
    - Uptime Kuma:
        icon: uptime-kuma
        href: https://status.${DOMAIN}
        description: Status & Latency

- Media Stack:
    - Plex Server:
        icon: plex
        href: https://plex.${DOMAIN}
        description: Media Streaming
    - Overseerr:
        icon: overseerr
        href: https://overseerr.${DOMAIN}
        description: Media Requests
    - Requestrr:
        icon: discord
        href: https://requestrr.${DOMAIN}
        description: Discord Request Bot
    - SABnzbd:
        icon: sabnzbd
        href: http://192.168.11.61:8080
        description: Usenet Downloader
    - Sonarr:
        icon: sonarr
        href: http://192.168.11.62:8989
        description: TV Shows Manager
    - Radarr:
        icon: radarr
        href: http://192.168.11.63:7878
        description: Movies Manager
    - Prowlarr:
        icon: prowlarr
        href: http://192.168.11.64:9696
        description: Indexer Sync
EOF

echo "==> Writing widgets.yaml"
cat > /opt/homepage/config/widgets.yaml << EOF
- logo:
    icon: https://raw.githubusercontent.com/gethomepage/homepage/main/public/android-chrome-192x192.png
- datetime:
    text_size: xl
    format:
      dateStyle: long
      timeStyle: short
      hour12: false
- resources:
    cpu: true
    memory: true
    disk: /
EOF

echo "==> Launching Homepage container"
cd /opt/homepage
docker compose down || true
docker compose up -d

# ── node_exporter ─────────────────────────────────────────────────────────────
echo "==> Installing node_exporter"
apt-get install -y -qq prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

# ── Trivy Container Vulnerability Scanner ─────────────────────────────────────
echo "==> Installing and configuring Trivy Docker security scanner"
apt-get install -y -qq apt-transport-https gnupg lsb-release wget
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/trivy.list
apt-get update -qq
apt-get install -y -qq trivy

cat > /usr/local/bin/trivy-container-scan.sh << 'EOF'
#!/usr/bin/env bash
images=$(docker ps --format "{{.Image}}")
log_path="/var/log/trivy-scan.log"

for img in $images; do
  trivy image --severity HIGH,CRITICAL --format json -q "$img" > /tmp/trivy_report.json || continue
  python3 -c "
import json
import sys
try:
    with open('/tmp/trivy_report.json', 'r') as f:
        data = json.load(f)
    results = data.get('Results', [])
    for res in results:
        vulns = res.get('Vulnerabilities', [])
        for v in vulns:
            entry = {
                'integration': 'trivy-docker',
                'image': '$img',
                'vulnerability': v.get('VulnerabilityID'),
                'severity': v.get('Severity'),
                'package': v.get('PkgName'),
                'installed_version': v.get('InstalledVersion'),
                'fixed_version': v.get('FixedVersion', 'None')
            }
            print(json.dumps(entry))
except Exception as e:
    pass
" >> "$log_path"
done
EOF
chmod +x /usr/local/bin/trivy-container-scan.sh

# Run once now to populate initial logs
/usr/local/bin/trivy-container-scan.sh || true

# Schedule weekly cron (Sundays at 2:00 AM)
echo "0 2 * * 0 root /usr/local/bin/trivy-container-scan.sh" > /etc/cron.d/trivy-container-scan

# Integrate with Wazuh agent localfile log reader
AGENT_CONFIG="/var/ossec/etc/ossec.conf"
if [ -f "$AGENT_CONFIG" ] && ! grep -q "/var/log/trivy-scan.log" "$AGENT_CONFIG"; then
  echo "Integrating Trivy logs with local Wazuh agent config"
  sed -i "s|.*</ossec_config>.*|<localfile>\n    <log_format>json</log_format>\n    <location>/var/log/trivy-scan.log</location>\n  </localfile>\n</ossec_config>|" "$AGENT_CONFIG"
  systemctl restart wazuh-agent || true
fi

echo "==> Homepage setup complete!"
