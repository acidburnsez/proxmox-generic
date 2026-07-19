#!/usr/bin/env bash
# Installs Authelia SSO/MFA service.
# Called by Terraform null_resource — do not run manually.

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive

# Load secrets written by Terraform file provisioner
if [ -f /tmp/.authelia_secrets ]; then
  . /tmp/.authelia_secrets
fi

DOMAIN="${DOMAIN:-example.com}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
JWT_SECRET="${JWT_SECRET}"
SESSION_SECRET="${SESSION_SECRET}"
ENCRYPTION_KEY="${ENCRYPTION_KEY}"

echo "==> Creating authelia system user"
useradd --system --shell /bin/false --user-group authelia || true

echo "==> Installing dependencies"
apt-get update -qq
apt-get install -y -qq curl tar ca-certificates sqlite3

echo "==> Downloading Authelia binary"
AUTHELIA_VERSION="4.39.20"
TARBALL_URL="https://github.com/authelia/authelia/releases/download/v${AUTHELIA_VERSION}/authelia-v${AUTHELIA_VERSION}-linux-amd64.tar.gz"

curl -sSL -o /tmp/authelia.tar.gz "${TARBALL_URL}"
tar -xzf /tmp/authelia.tar.gz -C /tmp/

# Safely extract the exact binary, preventing authelia.service from overwriting it
if [ -f /tmp/authelia ]; then
  mv /tmp/authelia /usr/local/bin/authelia
elif [ -f /tmp/authelia-linux-amd64 ]; then
  mv /tmp/authelia-linux-amd64 /usr/local/bin/authelia
else
  # Exclude .service files from matching wildcards
  find /tmp -type f -name "authelia*" ! -name "*.tar.gz" ! -name "*.service" -exec mv {} /usr/local/bin/authelia \;
fi

chmod +x /usr/local/bin/authelia
rm -f /tmp/authelia.tar.gz

echo "==> Preparing directories"
mkdir -p /etc/authelia
mkdir -p /var/lib/authelia

echo "==> Generating Argon2id password hash for admin user admin"
RAW_HASH=$(/usr/local/bin/authelia crypto hash generate argon2 --password "${ADMIN_PASSWORD}")
PASSWORD_HASH=$(echo "${RAW_HASH}" | grep -o '\$argon2id\$.*')

echo "==> Writing users.yml database"
cat > /var/lib/authelia/users.yml << EOF
users:
  admin:
    displayname: "Administrator"
    password: "${PASSWORD_HASH}"
    email: "admin@${DOMAIN}"
    groups:
      - admins
      - users
EOF

echo "==> Generating OIDC token signing private key if not present"
OIDC_KEY_FILE="/etc/authelia/oidc_key_pkcs8.pem"
if [ ! -f "$OIDC_KEY_FILE" ]; then
  openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -outform PEM > "$OIDC_KEY_FILE"
  chown authelia:authelia "$OIDC_KEY_FILE"
  chmod 600 "$OIDC_KEY_FILE"
fi
OIDC_KEY_CONTENT=$(cat "$OIDC_KEY_FILE" | sed 's/^/        /')

echo "==> Writing configuration.yml"
cat > /etc/authelia/configuration.yml << EOF
theme: light

identity_validation:
  reset_password:
    jwt_secret: "${JWT_SECRET}"

server:
  address: "tcp://0.0.0.0:9091/"

log:
  level: info

totp:
  issuer: auth.${DOMAIN}

webauthn:
  display_name: "Personal Production SSO"
  enable_passkey_login: true

authentication_backend:
  file:
    path: /var/lib/authelia/users.yml
    password:
      algorithm: argon2
      argon2:
        variant: argon2id
        iterations: 3
        memory: 65536
        parallelism: 4
        key_length: 32

storage:
  local:
    path: /var/lib/authelia/db.sqlite3
  encryption_key: "${ENCRYPTION_KEY}"

session:
  secret: "${SESSION_SECRET}"
  cookies:
    - domain: "${DOMAIN}"
      authelia_url: "https://auth.${DOMAIN}"
      default_redirection_url: "https://grafana.${DOMAIN}"
      name: "authelia_session"
      same_site: "lax"
      expiration: "3600"
      inactivity: "900"

access_control:
  default_policy: deny
  rules:
    - domain: "auth.${DOMAIN}"
      policy: bypass
    - domain: "*.${DOMAIN}"
      policy: one_factor
    - domain: "plex.${DOMAIN}"
      policy: bypass
    - domain: "overseerr.${DOMAIN}"
      policy: bypass
    - domain: "requestrr.${DOMAIN}"
      policy: bypass

notifier:
  filesystem:
    filename: /var/lib/authelia/notification.txt

identity_providers:
  oidc:
    cors:
      allowed_origins_from_client_redirect_uris: true
    issuer_private_key: |
${OIDC_KEY_CONTENT}
    clients:
      - client_id: wazuh
        client_name: Wazuh Dashboard
        client_secret: '\$pbkdf2-sha512\$310000\$oTVmqDV8yP99wUWSDXuiEQ\$jjB3RrjlfJbq.FnsMoTPzJOjsihrmNJpwkKmo9vIkN717NzHe./ufahLC0qeYXUtYVp9TtmQDLdQaC4DtXMO3A'
        public: false
        authorization_policy: one_factor
        redirect_uris:
          - https://wazuh.example.com/auth/openid/login
        scopes:
          - openid
          - profile
          - email
          - groups
          - address
          - phone
        userinfo_signed_response_alg: none
        token_endpoint_auth_method: 'client_secret_post'
      - client_id: gitea
        client_name: Gitea Server
        client_secret: '\$pbkdf2-sha512\$310000\$4o48I.oQcxAHLsxk2vrD0A\$X4TA2zFs0s/GAyX/aIdu7TdypNtw5BDLOmELCAaNf3UPgUyh5.3JDO4LfGOp3Fg2t24ao4C1qKjyHgPJP7Jmrg'
        public: false
        authorization_policy: one_factor
        redirect_uris:
          - https://gitea.example.com/user/oauth2/Authelia/callback
        scopes:
          - openid
          - profile
          - email
          - groups
        userinfo_signed_response_alg: none
EOF

echo "==> Setting permissions"
chown -R authelia:authelia /etc/authelia /var/lib/authelia
chmod 750 /etc/authelia /var/lib/authelia
chmod 640 /etc/authelia/configuration.yml /var/lib/authelia/users.yml

echo "==> Creating systemd service file"
cat > /etc/systemd/system/authelia.service << 'EOF'
[Unit]
Description=Authelia SSO Portal
After=network.target

[Service]
Type=simple
User=authelia
Group=authelia
WorkingDirectory=/var/lib/authelia
ExecStart=/usr/local/bin/authelia --config /etc/authelia/configuration.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Starting Authelia"
systemctl daemon-reload
systemctl enable authelia
systemctl restart authelia

# ── node_exporter ─────────────────────────────────────────────────────────────
echo "==> Installing node_exporter"
apt-get install -y -qq prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo "==> Authelia setup complete!"
