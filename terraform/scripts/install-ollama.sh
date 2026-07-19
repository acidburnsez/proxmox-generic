#!/usr/bin/env bash
# Run INSIDE the Ollama container after terraform apply.
#
# Tested for: Nvidia driver 595.80 on Proxmox 8.x

set -euo pipefail

# Idempotency — skip if Ollama is already installed and running
if systemctl is-active --quiet ollama 2>/dev/null; then
  echo "==> Ollama already running, checking model status..."
else
  # ── Config ────────────────────────────────────────────────────────────────────
  # Must exactly match the host driver version
  NVIDIA_DRIVER_VERSION="${NVIDIA_DRIVER_VERSION:-595.80}"

  # ── Nvidia userspace libraries ────────────────────────────────────────────────
  echo "==> Attempting Nvidia userspace libraries (${NVIDIA_DRIVER_VERSION})"
  RUNFILE="NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run"
  RUNFILE_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_DRIVER_VERSION}/${RUNFILE}"

  apt update -qq
  apt install -y curl wget kmod zstd -qq

  # Remove conflicting drivers
  apt remove -y --purge "nvidia-driver-*" "nvidia-utils-*" "libnvidia-*" 2>/dev/null || true

  if nvidia-smi 2>/dev/null | grep -q "${NVIDIA_DRIVER_VERSION}"; then
    echo "==> Nvidia ${NVIDIA_DRIVER_VERSION} already installed"
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
      echo "WARNING: Could not download Nvidia runfile — CUDA offloading may not function"
    fi
  fi

  if nvidia-smi 2>/dev/null; then
    echo "==> Nvidia GPU integration OK"
  else
    echo "WARNING: nvidia-smi not available"
  fi

  # ── Install Ollama ───────────────────────────────────────────────────────────
  echo "==> Installing Ollama"
  curl -fsSL https://ollama.com/install.sh | sh

  # Configure Ollama to listen on 0.0.0.0
  echo "==> Configuring Ollama systemd service environment"
  mkdir -p /etc/systemd/system/ollama.service.d
  cat << 'EOF' > /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_NUM_PARALLEL=4"
Environment="OLLAMA_MAX_QUEUE=512"
EOF

  systemctl daemon-reload
  systemctl enable ollama
  systemctl restart ollama
fi

# ── Pull Default Model ────────────────────────────────────────────────────────
echo "==> Pulling Llama-3-8B model..."
# Ensure Ollama is ready to accept requests before pulling
for i in {1..30}; do
  if curl -s http://127.0.0.1:11434/api/tags >/dev/null; then
    break
  fi
  sleep 1
done

ollama pull llama3:8b

# ── node_exporter ─────────────────────────────────────────────────────────────
echo "==> Installing node_exporter"
apt install -y prometheus-node-exporter -qq
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo "==> Ollama installation completed successfully!"
