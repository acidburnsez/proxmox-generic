#!/usr/bin/env bash
# Installs Uptime Kuma status page.
# Called by Terraform null_resource — do not run manually.

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive

echo "==> Installing Docker and dependencies"
apt-get update -qq
apt-get install -y -qq docker.io docker-compose-v2 curl

echo "==> Creating Uptime Kuma directories"
mkdir -p /opt/uptime-kuma

echo "==> Writing docker-compose.yml"
cat > /opt/uptime-kuma/docker-compose.yml << EOF
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    ports:
      - 3001:3001
    volumes:
      - /opt/uptime-kuma/data:/app/data
    restart: unless-stopped
EOF

echo "==> Launching Uptime Kuma container"
cd /opt/uptime-kuma
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

echo "==> Uptime Kuma setup complete!"
