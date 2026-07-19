#!/usr/bin/env bash
# Installs Tailscale and configures it as a subnet router.
# Called by Terraform null_resource — do not run manually.
#
# After apply, approve the subnet route in the Tailscale admin panel:
#   https://login.tailscale.com/admin/machines
#   Click the machine → Edit route settings → enable 192.168.11.0/24

set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

TS_AUTHKEY="${1}"
ADVERTISE_ROUTES="${2:-192.168.11.0/24}"

echo "==> Installing prerequisites"
apt-get update -qq
apt-get install -y curl ca-certificates

echo "==> Enabling IP forwarding"
cat >> /etc/sysctl.conf << 'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
/sbin/sysctl -p /etc/sysctl.conf

echo "==> Installing Tailscale"
curl -fsSL https://tailscale.com/install.sh | sh

echo "==> Starting Tailscale"
tailscale up \
  --authkey="${TS_AUTHKEY}" \
  --advertise-routes="${ADVERTISE_ROUTES}" \
  --accept-dns=false \
  --hostname="proxmox-personal-production"

echo ""
echo "==> Done! Tailscale is up."
echo ""
echo "Next steps:"
echo "  1. Go to https://login.tailscale.com/admin/machines"
echo "  2. Find 'proxmox-personal-production' and click Edit route settings"
echo "  3. Enable the ${ADVERTISE_ROUTES} subnet route"
echo "  4. You can now reach all personal production services over Tailscale"
