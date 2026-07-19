#!/usr/bin/env bash
# Run on the PROXMOX HOST (not inside a container) before terraform apply.
# Tested on: Proxmox 8.x (Bookworm) and Proxmox 9.x (Trixie)
# GPU: RTX 2070 Super (Turing / TU104)
#
#   scp setup-proxmox-nvidia.sh root@<proxmox-ip>:~
#   ssh root@<proxmox-ip> bash setup-proxmox-nvidia.sh
#
# A reboot is required at the end.

set -euo pipefail

DRIVER_VERSION="535"

# ── Detect Proxmox / Debian version ──────────────────────────────────────────

DEBIAN_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
echo "==> Detected Debian: ${DEBIAN_CODENAME}"

# ── Check DNS before doing anything ──────────────────────────────────────────

echo "==> Checking network / DNS"
if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
  echo "ERROR: Cannot reach 8.8.8.8 — check your network interface config"
  exit 1
fi
if ! getent hosts deb.debian.org &>/dev/null; then
  echo "WARNING: DNS not resolving. Temporarily setting nameserver to 8.8.8.8"
  echo "nameserver 8.8.8.8" > /etc/resolv.conf
  echo "Set a permanent DNS server in Proxmox UI: System → DNS"
fi

# ── Check for existing Nvidia driver ─────────────────────────────────────────

echo "==> Checking for existing Nvidia driver"
if nvidia-smi &>/dev/null; then
  echo "Nvidia driver already installed:"
  nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
  exit 0
fi

# ── Fix Proxmox repos (disable enterprise, enable no-subscription) ────────────

echo "==> Configuring Proxmox repos"

# Disable enterprise repos (require a paid subscription key)
for f in /etc/apt/sources.list.d/pve-enterprise.list \
          /etc/apt/sources.list.d/ceph.list \
          /etc/apt/sources.list.d/ceph-enterprise.list; do
  if [ -f "$f" ] && grep -qv '^#' "$f" 2>/dev/null; then
    echo "# disabled - no subscription (setup-proxmox-nvidia.sh)" > "$f"
    echo "  Disabled: $f"
  fi
done

# Add free no-subscription repos if not already present
PVE_FREE="/etc/apt/sources.list.d/pve-no-subscription.list"
if [ ! -f "$PVE_FREE" ] || ! grep -q 'pve-no-subscription' "$PVE_FREE" 2>/dev/null; then
  echo "deb http://download.proxmox.com/debian/pve ${DEBIAN_CODENAME} pve-no-subscription" \
    > "$PVE_FREE"
  echo "  Added: $PVE_FREE"
fi

CEPH_FREE="/etc/apt/sources.list.d/ceph-no-subscription.list"
if [ ! -f "$CEPH_FREE" ] || ! grep -q 'no-subscription' "$CEPH_FREE" 2>/dev/null; then
  echo "deb http://download.proxmox.com/debian/ceph-squid ${DEBIAN_CODENAME} no-subscription" \
    > "$CEPH_FREE"
  echo "  Added: $CEPH_FREE"
fi

# ── Blacklist nouveau ─────────────────────────────────────────────────────────

echo "==> Blacklisting nouveau"
cat > /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
update-initramfs -u

# ── Install kernel headers ────────────────────────────────────────────────────

echo "==> Installing Proxmox kernel headers"
apt-get update -qq

# The headers package is named after the running kernel on PVE 9.x
KERNEL_VERSION=$(uname -r)
if apt-cache show "pve-headers-${KERNEL_VERSION}" &>/dev/null; then
  apt-get install -y "pve-headers-${KERNEL_VERSION}"
elif apt-cache show "proxmox-headers-${KERNEL_VERSION}" &>/dev/null; then
  apt-get install -y "proxmox-headers-${KERNEL_VERSION}"
elif apt-cache show "pve-headers" &>/dev/null; then
  apt-get install -y pve-headers
else
  echo "ERROR: Could not find kernel headers package for ${KERNEL_VERSION}"
  echo "Try manually: apt-cache search pve-headers"
  exit 1
fi

# ── Add non-free repo ─────────────────────────────────────────────────────────

echo "==> Enabling non-free packages"
if [ -f /etc/apt/sources.list ]; then
  # Only modify if non-free not already present
  if ! grep -q 'non-free' /etc/apt/sources.list; then
    sed -i 's/main contrib/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
  fi
fi

# Trixie may keep sources in sources.list.d instead
for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
  [ -f "$f" ] || continue
  if grep -q "${DEBIAN_CODENAME}" "$f" && ! grep -q 'non-free' "$f"; then
    sed -i 's/main contrib/main contrib non-free non-free-firmware/g' "$f"
  fi
done

apt-get update -qq

# ── Install Nvidia driver ─────────────────────────────────────────────────────

echo "==> Installing Nvidia driver ${DRIVER_VERSION}"

# Try versioned package name, fall back to unversioned if not found (varies by distro)
if apt-cache show "nvidia-driver-${DRIVER_VERSION}" &>/dev/null; then
  apt-get install -y "nvidia-driver-${DRIVER_VERSION}"
elif apt-cache show "nvidia-driver" &>/dev/null; then
  echo "WARNING: nvidia-driver-${DRIVER_VERSION} not found, installing latest available"
  apt-get install -y nvidia-driver
else
  echo "ERROR: No nvidia-driver package found. Check your non-free repo is enabled."
  echo "Run: apt-cache search nvidia-driver"
  exit 1
fi

echo ""
echo "==> Driver installed. Rebooting is required for it to take effect."
echo ""
echo "    reboot"
echo ""
echo "After rebooting, verify with:  nvidia-smi"
echo "You should see: NVIDIA GeForce RTX 2070 SUPER"
echo ""
echo "Then run terraform apply from your local machine."
