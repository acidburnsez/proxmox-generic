#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq curl sqlite3

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH_SUFFIX="x64" ;;
  aarch64) ARCH_SUFFIX="arm64" ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

# Get latest release URL
URL=$(curl -fsSL "https://api.github.com/repos/Sonarr/Sonarr/releases/latest" \
  | grep "browser_download_url" \
  | grep "linux-${ARCH_SUFFIX}.tar.gz" \
  | cut -d'"' -f4 | head -1)

echo "Downloading Sonarr from $URL"
curl -fsSL "$URL" -o /tmp/sonarr.tar.gz
tar -xzf /tmp/sonarr.tar.gz -C /opt
rm /tmp/sonarr.tar.gz

mkdir -p /media/tv /media/downloads/complete /var/lib/sonarr

# Sonarr v4 drops from root to its own 'sonarr' user on startup.
# Ensure it can write to its media directory.
getent group sonarr  || groupadd -r sonarr
getent passwd sonarr || useradd  -r -g sonarr -d /var/lib/sonarr sonarr
chown -R sonarr:sonarr /media/tv /var/lib/sonarr

cat > /etc/systemd/system/sonarr.service << 'EOF'
[Unit]
Description=Sonarr
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/opt/Sonarr/Sonarr -nobrowser -data=/var/lib/sonarr
TimeoutStopSec=20
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sonarr
systemctl start sonarr

# ── node_exporter ─────────────────────────────────────────────────────────────
apt-get install -y -qq prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo "Sonarr installed — http://$(hostname -I | awk '{print $1}'):8989"
echo "node_exporter running on :9100"
