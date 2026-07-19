#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ── Node.js 20.x ──────────────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq curl git

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y -qq nodejs

npm install -g yarn
YARN=$(which yarn)

# ── Overseerr ─────────────────────────────────────────────────────────────────
VERSION=$(curl -fsSL "https://api.github.com/repos/sct/overseerr/releases/latest" \
  | grep '"tag_name"' | cut -d'"' -f4)

echo "==> Cloning Overseerr ${VERSION}"
rm -rf /opt/overseerr
git clone --depth 1 --branch "$VERSION" https://github.com/sct/overseerr.git /opt/overseerr

cd /opt/overseerr
echo "==> Installing dependencies (this takes a few minutes)"
CYPRESS_INSTALL_BINARY=0 "$YARN" install --frozen-lockfile --network-timeout 300000

echo "==> Building Overseerr"
"$YARN" build

mkdir -p /var/lib/overseerr

# ── Systemd service ───────────────────────────────────────────────────────────
cat > /etc/systemd/system/overseerr.service << SVCEOF
[Unit]
Description=Overseerr
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/overseerr
Environment=NODE_ENV=production
Environment=CONFIG_DIRECTORY=/var/lib/overseerr
ExecStart=${YARN} start
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable overseerr
systemctl start overseerr

# ── node_exporter ─────────────────────────────────────────────────────────────
apt-get install -y -qq prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo "==> Overseerr installed — http://$(hostname -I | awk '{print $1}'):5055"
echo "==> node_exporter running on :9100"
