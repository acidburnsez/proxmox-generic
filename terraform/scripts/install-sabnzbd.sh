#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq sabnzbdplus

# Create media directories
mkdir -p /media/downloads/incomplete /media/downloads/complete

# Configure SABnzbd to run as root and listen on all interfaces
CONF_DIR="/root/.config/sabnzbd"
mkdir -p "$CONF_DIR"

# Enable external access and set download paths via ini
cat > "$CONF_DIR/sabnzbd.ini" << 'EOF'
[misc]
host = 0.0.0.0
port = 8080
download_dir = /media/downloads/incomplete
complete_dir = /media/downloads/complete
EOF

cat > /etc/default/sabnzbdplus << 'EOF'
USER=root
HOST=0.0.0.0
PORT=8080
EXTRAOPTS=
EOF

systemctl enable sabnzbdplus
systemctl restart sabnzbdplus

# ── node_exporter ─────────────────────────────────────────────────────────────
apt-get install -y -qq prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo "SABnzbd installed — http://$(hostname -I | awk '{print $1}'):8080"
echo "node_exporter running on :9100"
