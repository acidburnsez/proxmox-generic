#!/usr/bin/env bash
# Installs Gitea Git Server.
# Called by Terraform null_resource — do not run manually.

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive

echo "==> Installing Docker and dependencies"
apt-get update -qq
apt-get install -y -qq docker.io docker-compose-v2 curl

echo "==> Creating Gitea directories"
mkdir -p /opt/gitea/data
mkdir -p /opt/gitea/runner-data

echo "==> Writing docker-compose.yml"
cat > /opt/gitea/docker-compose.yml << EOF
services:
  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    environment:
      - USER_UID=1000
      - USER_GID=1000
    ports:
      - "3000:3000"
      - "222:22"
    volumes:
      - /opt/gitea/data:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: unless-stopped

  runner:
    image: gitea/act_runner:latest
    container_name: gitea-runner
    environment:
      - GITEA_INSTANCE_URL=http://192.168.11.69:3000
      - GITEA_RUNNER_REGISTRATION_TOKEN=QRztszuSlVDzxZp49Hxtko1SS7GDXJjpVI96bV6W
      - GITEA_RUNNER_NAME=homelab-runner
      - GITEA_RUNNER_LABELS=ubuntu-latest:docker://node:16-bullseye,ubuntu-22.04:docker://node:16-bullseye,ubuntu-20.04:docker://node:16-bullseye
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/gitea/runner-data:/data
    restart: unless-stopped
    depends_on:
      - gitea
EOF

echo "==> Launching Gitea container"
cd /opt/gitea
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

echo "==> Gitea setup complete!"
