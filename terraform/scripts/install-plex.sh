#!/usr/bin/env bash
# Run INSIDE the Plex container after terraform apply.
#
#   ssh root@192.168.11.60 "bash -s" < install-plex.sh
#
# Tested for: RTX 2070 Super (Turing / TU104) on Proxmox 8.x
#
# Prerequisites on the PROXMOX HOST (run once before terraform apply):
#   See scripts/setup-proxmox-nvidia.sh

set -euo pipefail

# Idempotency — skip if Plex is already installed and running
if systemctl is-active --quiet plexmediaserver 2>/dev/null; then
  echo "==> Plex already running, skipping install"
  exit 0
fi

# ── Config ────────────────────────────────────────────────────────────────────
# Must exactly match the runfile version installed on the Proxmox host.
# The container shares the host kernel module — only userspace libs are installed.
# Check host version with: nvidia-smi --query-gpu=driver_version --format=csv,noheader
NVIDIA_DRIVER_VERSION="${NVIDIA_DRIVER_VERSION:-595.80}"

# ── Nvidia userspace libraries (optional) ─────────────────────────────────────
# Best-effort — Plex installs regardless. Hardware transcoding requires Plex Pass.
echo "==> Attempting Nvidia userspace libraries (${NVIDIA_DRIVER_VERSION})"
RUNFILE="NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run"
RUNFILE_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_DRIVER_VERSION}/${RUNFILE}"

apt-get update -qq
apt-get install -y curl wget kmod

# Remove any conflicting apt-installed drivers first
apt-get remove -y --purge "nvidia-driver-*" "nvidia-utils-*" "libnvidia-*" 2>/dev/null || true

if nvidia-smi 2>/dev/null | grep -q "${NVIDIA_DRIVER_VERSION}"; then
  echo "==> Nvidia ${NVIDIA_DRIVER_VERSION} already installed, skipping"
else
  if wget -q -O "/tmp/${RUNFILE}" "${RUNFILE_URL}"; then
    chmod +x "/tmp/${RUNFILE}"
    "/tmp/${RUNFILE}" \
      --no-kernel-modules \
      --no-questions \
      --ui=none \
      --disable-nouveau \
      --no-systemd || true
    rm -f "/tmp/${RUNFILE}"
  else
    echo "WARNING: Could not download Nvidia runfile — skipping GPU setup"
  fi
fi

if nvidia-smi 2>/dev/null; then
  echo "==> Nvidia OK"
else
  echo "WARNING: nvidia-smi not available — hardware transcoding will not work"
  echo "  - Confirm host driver version matches ${NVIDIA_DRIVER_VERSION}"
  echo "  - Confirm /dev/nvidia* devices exist and container is privileged"
fi

# ── Plex Media Server ─────────────────────────────────────────────────────────
echo "==> Installing Plex Media Server"
apt-get install -y curl gnupg

curl -fsSL https://downloads.plex.tv/plex-keys/PlexSign.key \
  | gpg --dearmor | tee /usr/share/keyrings/plex.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/plex.gpg] https://downloads.plex.tv/repo/deb public main" \
  > /etc/apt/sources.list.d/plexmediaserver.list

apt-get update -qq
apt-get install -y plexmediaserver

systemctl enable plexmediaserver
systemctl start plexmediaserver

# ── node_exporter ─────────────────────────────────────────────────────────────
echo "==> Installing node_exporter"
apt-get install -y prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo ""
echo "==> Done!"
echo ""
echo "Next steps:"
echo "  1. Open http://192.168.11.60:32400/web to claim and set up your server"
echo "  2. Add your media library (path: /media) in the Plex UI"
echo "  3. Enable Hardware-Accelerated Encoding:"
echo "       Plex Settings -> Transcoder -> Use hardware acceleration when available"
echo "       NOTE: Requires Plex Pass subscription for NVENC on RTX 2070 Super"
echo "  4. Add Plex to Prometheus scrape config: 192.168.11.60:9100"
