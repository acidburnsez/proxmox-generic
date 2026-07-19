#!/usr/bin/env bash
# Installs HashiCorp Vault & Tailscale inside the LXC container.
# Configures the Vault Token Dispenser daemon.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

TAILSCALE_KEY="${1:-}"

# 1. Install dependencies
echo "==> Installing basic dependencies"
apt-get update -qq
apt-get install -y -qq curl wget gpg lsb-release ca-certificates python3

# 2. Add HashiCorp Repository & Install Vault
if ! dpkg -s vault >/dev/null 2>&1; then
  echo "==> Adding HashiCorp repository"
  wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
  
  echo "==> Installing HashiCorp Vault"
  apt-get update -qq
  apt-get install -y -qq vault
else
  echo "==> Vault already installed"
fi

# 3. Configure Vault
echo "==> Configuring Vault server"
mkdir -p /opt/vault/data
chown -R vault:vault /opt/vault

cat > /etc/vault.d/vault.hcl << 'EOF'
storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

# Essential for running Vault inside unprivileged LXC without IPC_LOCK capability
disable_mlock = true

api_addr = "http://127.0.0.1:8200"
ui = true
EOF

chown vault:vault /etc/vault.d/vault.hcl

# 4. Install & Configure Tailscale
if ! command -v tailscale >/dev/null 2>&1; then
  echo "==> Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

if [ -n "${TAILSCALE_KEY}" ]; then
  echo "==> Authenticating Tailscale node"
  tailscale up --authkey="${TAILSCALE_KEY}" --hostname="vault" --accept-routes=false
fi

# 5. Set up Token Dispenser Service
echo "==> Setting up Token Dispenser python sidecar"
cp -f /tmp/vault-token-dispenser.py /usr/local/bin/vault-token-dispenser.py
chmod +x /usr/local/bin/vault-token-dispenser.py

cat > /etc/systemd/system/vault-token-dispenser.service << 'EOF'
[Unit]
Description=Tailscale-to-Vault Token Dispenser
After=network.target tailscaled.service vault.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 -u /usr/local/bin/vault-token-dispenser.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 6. Enable and Start Services
echo "==> Enabling and starting services"
systemctl daemon-reload
systemctl enable vault.service vault-token-dispenser.service
systemctl restart vault.service
systemctl restart vault-token-dispenser.service

echo "==> Vault and Token Dispenser installation completed successfully!"
