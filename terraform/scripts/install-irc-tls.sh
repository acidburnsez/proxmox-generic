#!/usr/bin/env bash
# Issues a real TLS cert for irc.<domain> and updates Ergo to use it.
# Replaces the self-signed cert created during initial Ergo install.
# Called by Terraform null_resource — do not run manually.
#
# Usage: install-irc-tls.sh <domain>
#   Expects /tmp/.cf_token containing CF_TOKEN='...' written by Terraform.

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

DOMAIN="${1:-example.com}"
IRC_FQDN="irc.${DOMAIN}"
ACME="${HOME}/.acme.sh/acme.sh"
CERT_DIR="/etc/ergo"

# Load Cloudflare token
if [ -f /tmp/.cf_token ]; then
  . /tmp/.cf_token
  export CF_Token="${CF_TOKEN}"
fi

echo "==> Installing acme.sh dependencies"
apt-get update -qq
apt-get install -y curl socat cron

echo "==> Installing acme.sh"
if [ ! -f "${ACME}" ]; then
  curl -fsSL https://get.acme.sh | sh -s email="admin@${DOMAIN}"
fi

echo "==> Issuing cert for ${IRC_FQDN}"
# Check if we already have a real cert (not the self-signed one)
ALREADY_ISSUED=false
if "${ACME}" --list 2>/dev/null | grep -q "${IRC_FQDN}"; then
  ALREADY_ISSUED=true
fi

if [ "${ALREADY_ISSUED}" = false ]; then
  "${ACME}" --issue \
    --dns dns_cf \
    -d "${IRC_FQDN}" \
    --server letsencrypt \
    --keylength ec-256 || {
      rc=$?
      [ $rc -eq 2 ] || { echo "acme.sh failed (rc=$rc)"; exit $rc; }
    }
fi

echo "==> Installing cert for Ergo"
"${ACME}" --install-cert \
  -d "${IRC_FQDN}" \
  --ecc \
  --cert-file     "${CERT_DIR}/tls.crt" \
  --key-file      "${CERT_DIR}/tls.key" \
  --fullchain-file "${CERT_DIR}/tls.crt" \
  --reloadcmd     "systemctl reload ergo 2>/dev/null || systemctl restart ergo"

chown ergo:ergo "${CERT_DIR}/tls.crt" "${CERT_DIR}/tls.key"
chmod 640 "${CERT_DIR}/tls.key"

echo "==> Reloading Ergo"
systemctl reload ergo 2>/dev/null || systemctl restart ergo

echo ""
echo "==> Done! IRC TLS cert issued for ${IRC_FQDN}"
echo "    Connect with: ${IRC_FQDN}:6697 (TLS — cert is now trusted)"
