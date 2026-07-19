#!/usr/bin/env bash
# Installs Gotify Notification Server on Ubuntu 24.04.
# Called by Terraform null_resource — do not run manually.

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive

echo "==> Updating package repository and installing unzip"
apt-get update -qq
apt-get install -y -qq wget unzip ca-certificates

echo "==> Creating Gotify directories"
mkdir -p /opt/gotify /etc/gotify /var/lib/gotify/images /var/lib/gotify/plugins

echo "==> Downloading Gotify Server v2.5.0"
cd /opt/gotify
wget -q https://github.com/gotify/server/releases/download/v2.5.0/gotify-linux-amd64.zip -O gotify.zip
unzip -o gotify.zip
rm -f gotify.zip
chmod +x gotify-linux-amd64

echo "==> Creating Gotify configuration file"
cat > /etc/gotify/config.yml << 'EOF'
server:
  port: 80
database:
  dialect: sqlite3
  connection: /var/lib/gotify/gotify.db
passstrength: 10
uploadedimagesdir: /var/lib/gotify/images
pluginsdir: /var/lib/gotify/plugins
EOF

echo "==> Creating Gotify systemd service"
cat > /etc/systemd/system/gotify.service << 'EOF'
[Unit]
Description=Gotify Notification Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/lib/gotify
ExecStart=/opt/gotify/gotify-linux-amd64
Restart=always
RestartSec=5
Environment=GOTIFY_DEFAULTUSER_NAME=admin
Environment=GOTIFY_DEFAULTUSER_PASS=admin

[Install]
WantedBy=multi-user.target
EOF

echo "==> Starting and enabling Gotify service"
systemctl daemon-reload
systemctl enable gotify
systemctl restart gotify

echo "==> Gotify installation completed successfully!"
