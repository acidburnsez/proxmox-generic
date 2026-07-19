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

URL=$(curl -fsSL "https://api.github.com/repos/Radarr/Radarr/releases/latest" \
  | grep "browser_download_url" \
  | grep "linux-core-${ARCH_SUFFIX}.tar.gz" \
  | cut -d'"' -f4 | head -1)

echo "Downloading Radarr from $URL"
curl -fsSL "$URL" -o /tmp/radarr.tar.gz
tar -xzf /tmp/radarr.tar.gz -C /opt
rm /tmp/radarr.tar.gz

mkdir -p /media/movies /media/downloads/complete /var/lib/radarr

# Radarr v4 drops from root to its own 'radarr' user on startup.
getent group radarr  || groupadd -r radarr
getent passwd radarr || useradd  -r -g radarr -d /var/lib/radarr radarr
chown -R radarr:radarr /media/movies /var/lib/radarr

cat > /etc/systemd/system/radarr.service << 'EOF'
[Unit]
Description=Radarr
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/opt/Radarr/Radarr -nobrowser -data=/var/lib/radarr
TimeoutStopSec=20
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable radarr
systemctl start radarr

# ── node_exporter ─────────────────────────────────────────────────────────────
apt-get install -y -qq prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo "Radarr installed — http://$(hostname -I | awk '{print $1}'):7878"
echo "node_exporter running on :9100"
