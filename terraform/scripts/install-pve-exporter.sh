#!/usr/bin/env bash
# Installs prometheus-pve-exporter inside an LXC container.
# Called by Terraform null_resource — do not run manually.
#
# Args:
#   $1  token_user   e.g. root@pam
#   $2  token_name   e.g. terraform
#   $3  token_value  e.g. xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

set -euo pipefail

TOKEN_USER="${1}"
TOKEN_NAME="${2}"
TOKEN_VALUE="${3}"

echo "==> Installing python3 + venv"
apt-get update -qq
apt-get install -y python3-pip python3-venv

echo "==> Installing prometheus-pve-exporter"
python3 -m venv /opt/pve-exporter
/opt/pve-exporter/bin/pip install --quiet prometheus-pve-exporter

echo "==> Writing config"
mkdir -p /etc/prometheus
cat > /etc/prometheus/pve.yml << EOF
default:
  user: ${TOKEN_USER}
  token_name: ${TOKEN_NAME}
  token_value: ${TOKEN_VALUE}
  verify_ssl: false
EOF
chmod 600 /etc/prometheus/pve.yml

echo "==> Creating systemd service"
cat > /etc/systemd/system/prometheus-pve-exporter.service << 'EOF'
[Unit]
Description=Prometheus PVE Exporter
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/pve-exporter/bin/pve_exporter --config.file /etc/prometheus/pve.yml --web.listen-address 0.0.0.0:9221
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prometheus-pve-exporter
systemctl restart prometheus-pve-exporter

echo "==> PVE exporter running on :9221"
