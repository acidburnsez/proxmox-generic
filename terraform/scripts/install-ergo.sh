#!/usr/bin/env bash
# Installs Ergo IRC daemon v2.18.0.
# Called by Terraform null_resource — do not run manually.
#
# Ports:
#   6667  plain IRC
#   6697  IRC over TLS (self-signed cert)
#
# After install, register your nick:
#   /connect irc.home 6697
#   /nick yournick
#   /msg NickServ REGISTER yourpassword youremail@example.com

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ERGO_VERSION="2.18.0"
ERGO_URL="https://github.com/ergochat/ergo/releases/download/v${ERGO_VERSION}/ergo-${ERGO_VERSION}-linux-x86_64.tar.gz"

# Idempotency
if systemctl is-active --quiet ergo 2>/dev/null; then
  echo "==> Ergo already running, skipping install"
  exit 0
fi

echo "==> Installing dependencies"
apt-get update -qq
apt-get install -y curl ca-certificates

echo "==> Downloading Ergo v${ERGO_VERSION}"
curl -fsSL "${ERGO_URL}" -o /tmp/ergo.tar.gz
tar -xzf /tmp/ergo.tar.gz -C /tmp
install -m 755 /tmp/ergo-${ERGO_VERSION}-linux-x86_64/ergo /usr/local/bin/ergo
rm -rf /tmp/ergo.tar.gz /tmp/ergo-${ERGO_VERSION}-linux-x86_64

echo "==> Creating ergo user and directories"
useradd -r -s /bin/false -d /var/lib/ergo ergo 2>/dev/null || true
mkdir -p /etc/ergo /var/lib/ergo
chown ergo:ergo /var/lib/ergo

echo "==> Generating TLS certificate"
apt-get install -y openssl
openssl req -x509 -newkey rsa:4096 -keyout /etc/ergo/tls.key -out /etc/ergo/tls.crt \
  -days 3650 -nodes -subj "/CN=irc.home" 2>/dev/null
chown ergo:ergo /etc/ergo/tls.key /etc/ergo/tls.crt
chmod 600 /etc/ergo/tls.key

echo "==> Writing config"
cat > /etc/ergo/ircd.yaml << 'EOF'
network:
  name: HomeNet

server:
  name: irc.home
  listeners:
    ":6667": {}
    ":6697":
      tls:
        cert: /etc/ergo/tls.crt
        key:  /etc/ergo/tls.key
  motd: ""
  motd-formatting: true
  max-sendq: 16M
  relaymsg:
    enabled: false

limits:
  nicklen: 32
  channellen: 64
  awaylen: 500
  kicklen: 1000
  topiclen: 1000

datastore:
  path: /var/lib/ergo/ircd.db

accounts:
  authentication-enabled: true
  registration:
    enabled: true
    allow-before-connect: true
    throttling:
      enabled: false
    email-verification:
      enabled: false
  nick-reservation:
    enabled: true
    method: strict
  require-sasl:
    enabled: false

channels:
  default-modes: +nt
  registration:
    enabled: true

history:
  enabled: true
  channel-length: 1024
  client-length: 256
  autoresize-window: 3d
  autoreplay-on-join: 0
  chathistory-maxmessages: 1000
  retention:
    allow-individual-user-delete: true
    enable-account-indexing: true

logging:
  - method: stderr
    level: warn
    type: "* -userinput -useroutput"

debug:
  recover-from-errors: true
EOF

chown ergo:ergo /etc/ergo/ircd.yaml

echo "==> Creating systemd service"
cat > /etc/systemd/system/ergo.service << 'EOF'
[Unit]
Description=Ergo IRC Server
After=network.target

[Service]
Type=simple
User=ergo
ExecStart=/usr/local/bin/ergo run --conf /etc/ergo/ircd.yaml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ergo
systemctl start ergo

echo ""
echo "==> Ergo IRC is running!"
echo ""
echo "Connect with any IRC client:"
echo "  Plain:  irc.home:6667  (or 192.168.11.55:6667)"
echo "  TLS:    irc.home:6697  (accept self-signed cert)"
echo ""
echo "Register your nick after connecting:"
echo "  /msg NickServ REGISTER <password> <email>"
