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

URL=$(curl -fsSL "https://api.github.com/repos/Prowlarr/Prowlarr/releases/latest" \
  | grep "browser_download_url" \
  | grep "linux-core-${ARCH_SUFFIX}.tar.gz" \
  | cut -d'"' -f4 | head -1)

echo "Downloading Prowlarr from $URL"
curl -fsSL "$URL" -o /tmp/prowlarr.tar.gz
tar -xzf /tmp/prowlarr.tar.gz -C /opt
rm /tmp/prowlarr.tar.gz

mkdir -p /var/lib/prowlarr

useradd -r -s /bin/false prowlarr 2>/dev/null || true
chown -R prowlarr:prowlarr /opt/Prowlarr /var/lib/prowlarr

cat > /etc/systemd/system/prowlarr.service << 'EOF'
[Unit]
Description=Prowlarr
After=network.target

[Service]
Type=simple
User=prowlarr
Group=prowlarr
ExecStart=/opt/Prowlarr/Prowlarr -nobrowser -data=/var/lib/prowlarr
TimeoutStopSec=20
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prowlarr
systemctl start prowlarr

# ── node_exporter ─────────────────────────────────────────────────────────────
apt-get install -y -qq prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo "Prowlarr installed — http://$(hostname -I | awk '{print $1}'):9696"
echo "node_exporter running on :9100"
