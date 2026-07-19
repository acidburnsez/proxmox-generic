#!/usr/bin/env bash
# Installs Requestrr Discord bot for media requests via Overseerr.
# Called by Terraform null_resource — do not run manually.
set -euo pipefail

INSTALL_DIR="/opt/requestrr"
SERVICE_USER="requestrr"

echo "==> Installing dependencies"
apt-get update -qq
apt-get install -y wget unzip

echo "==> Fetching latest Requestrr release"
LATEST=$(wget -qO- "https://api.github.com/repos/darkalfx/requestrr/releases/latest" \
  | grep '"tag_name"' | cut -d'"' -f4)
echo "    version: ${LATEST}"

ASSET_URL="https://github.com/darkalfx/requestrr/releases/download/${LATEST}/requestrr-linux-x64.zip"
wget -q "${ASSET_URL}" -O /tmp/requestrr.zip

echo "==> Installing to ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
unzip -o /tmp/requestrr.zip -d "${INSTALL_DIR}"
rm /tmp/requestrr.zip

# Binary lives in a nested subdirectory — find it
BINARY=$(find "${INSTALL_DIR}" -maxdepth 2 -name "Requestrr.WebApi" | head -1)
[ -z "${BINARY}" ] && { echo "ERROR: Requestrr.WebApi not found after extraction"; exit 1; }
WORK_DIR=$(dirname "${BINARY}")
chmod +x "${BINARY}"

echo "==> Creating service user"
getent passwd "${SERVICE_USER}" || useradd -r -d "${INSTALL_DIR}" -s /usr/sbin/nologin "${SERVICE_USER}"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"

echo "==> Writing systemd unit"
cat > /etc/systemd/system/requestrr.service << EOF
[Unit]
Description=Requestrr Discord Bot
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${WORK_DIR}
ExecStart=${BINARY}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Installing node_exporter"
apt-get install -y prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo "==> Starting Requestrr"
systemctl daemon-reload
systemctl enable requestrr
systemctl restart requestrr

echo ""
echo "==> Done! Requestrr running on :4545"
echo "    Open https://requestrr.example.com to complete setup:"
echo "    1. Set an admin password"
echo "    2. Paste your Discord bot token"
echo "    3. Point it at Overseerr: http://192.168.11.65:5055"
