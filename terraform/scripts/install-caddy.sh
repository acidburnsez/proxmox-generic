#!/usr/bin/env bash
# Installs Caddy with Cloudflare DNS-01 TLS plugin and CrowdSec IPS integration.
# Called by Terraform null_resource — do not run manually.

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive

DOMAIN="${1:-example.com}"

# Load Cloudflare token written by Terraform
if [ -f /tmp/.cf_token ]; then
  . /tmp/.cf_token
fi

echo "==> Creating caddy system user/group"
groupadd --system caddy || true
useradd --system \
    --gid caddy \
    --create-home \
    --home-dir /var/lib/caddy \
    --shell /usr/sbin/nologin \
    --comment "Caddy web server" \
    caddy || true

echo "==> Installing dependencies"
apt-get update -qq
apt-get install -y -qq curl libcap2-bin openssl

echo "==> Downloading Caddy binary with Cloudflare DNS & CrowdSec plugins"
# Downloads pre-built Caddy binary with cloudflare and crowdsec-bouncer plugins enabled
curl -sSL "https://caddyserver.com/api/download?os=linux&arch=amd64&p=github.com/caddy-dns/cloudflare&p=github.com/hslatman/caddy-crowdsec-bouncer" -o /tmp/caddy
mv /tmp/caddy /usr/bin/caddy
chmod +x /usr/bin/caddy

# Set capabilities so Caddy can bind to ports 80/443 without running as root
setcap cap_net_bind_service=+ep /usr/bin/caddy

echo "==> Creating Caddy directories"
mkdir -p /etc/caddy
mkdir -p /var/lib/caddy
mkdir -p /var/log/caddy
chown -R caddy:caddy /var/lib/caddy /etc/caddy /var/log/caddy
chmod 755 /var/log/caddy

echo "==> Installing CrowdSec Security Engine"
curl -s https://install.crowdsec.net | sh
apt-get update -qq
apt-get install -y -qq crowdsec

echo "==> Configuring CrowdSec log parsing for Caddy"
cat > /etc/crowdsec/acquis.yaml << EOF
filenames:
  - /var/log/caddy/access.log
labels:
  type: caddy
EOF

# Install Caddy logs parser and scenarios collection
cscli collections install crowdsecurity/caddy || true

# Generate a secure bouncer API key
BOUNCER_KEY=$(openssl rand -hex 16)
cscli bouncers delete caddy-bouncer || true
cscli bouncers add caddy-bouncer --key "${BOUNCER_KEY}"

systemctl restart crowdsec

echo "==> Writing Cloudflare API Token to environment file"
echo "CF_API_TOKEN=${CF_TOKEN}" > /etc/caddy/caddy.env
chmod 600 /etc/caddy/caddy.env
chown caddy:caddy /etc/caddy/caddy.env

echo "==> Writing Caddyfile"
cat > /etc/caddy/Caddyfile << EOF
{
    email admin@${DOMAIN}
    crowdsec {
        api_url http://localhost:8080
        api_key ${BOUNCER_KEY}
    }
}

# Reusable auth import block for Authelia SSO
(auth) {
    forward_auth 192.168.11.90:9091 192.168.11.91:9091 192.168.11.92:9091 {
        uri /api/verify?rd=https://auth.${DOMAIN}/
        copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
    }
}

# Wildcard domain router
*.${DOMAIN} {
    log {
        output file /var/log/caddy/access.log
        format json
    }
    
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }

    route {
        # Apple App Site Association for Passkeys
        handle /.well-known/apple-app-site-association {
            header Content-Type "application/json"
            respond \`{"webcredentials":{"apps":["27H9V537MH.com.secops.mobile.wazuh-ollama-ios"]}}\`
        }

        # Active CrowdSec IPS inspection
        crowdsec

        @website host user.${DOMAIN}
        handle @website {
            reverse_proxy 192.168.11.80:80
        }

        @homepage host homepage.${DOMAIN}
        handle @homepage {
            import auth
            reverse_proxy 192.168.11.90:3000 192.168.11.91:3000 192.168.11.92:3000
        }

        @gotify host gotify.${DOMAIN}
        handle @gotify {
            reverse_proxy 192.168.11.58:80
        }

        @status host status.${DOMAIN}
        handle @status {
            reverse_proxy 192.168.11.90:3001 192.168.11.91:3001 192.168.11.92:3001
        }

        @grafana host grafana.${DOMAIN}
        handle @grafana {
            import auth
            reverse_proxy 192.168.11.90:30030 192.168.11.91:30030 192.168.11.92:30030
        }

        @prometheus host prometheus.${DOMAIN}
        handle @prometheus {
            import auth
            reverse_proxy 192.168.11.90:30090 192.168.11.91:30090 192.168.11.92:30090
        }

        @plex host plex.${DOMAIN}
        handle @plex {
            reverse_proxy 192.168.11.90:32400 192.168.11.91:32400 192.168.11.92:32400
        }

        @gitea host gitea.${DOMAIN}
        handle @gitea {
            # Bypass Authelia for actions runners and package registries
            @bypass path /api/actions_pipeline/* /api/v1/packages/* /api/packages/*
            handle @bypass {
                reverse_proxy 192.168.11.69:3000
            }

            handle {
                import auth
                reverse_proxy 192.168.11.69:3000
            }
        }

        @argocd host argocd.${DOMAIN}
        handle @argocd {
            import auth
            reverse_proxy https://192.168.11.90:8082 https://192.168.11.91:8082 https://192.168.11.92:8082 {
                transport http {
                    tls_insecure_skip_verify
                }
            }
        }

        @longhorn host longhorn.${DOMAIN}
        handle @longhorn {
            import auth
            reverse_proxy 192.168.11.90:8083 192.168.11.91:8083 192.168.11.92:8083
        }

        @ollama host ollama.${DOMAIN}
        handle @ollama {
            reverse_proxy 192.168.11.90:11434 192.168.11.91:11434 192.168.11.92:11434
        }

        @neobear host chat.${DOMAIN}
        handle @neobear {
            import auth
            route /weechat {
                reverse_proxy 192.168.11.90:30091 192.168.11.91:30091 192.168.11.92:30091
            }
            route {
                reverse_proxy 192.168.11.90:30080 192.168.11.91:30080 192.168.11.92:30080
            }
        }

        @neodrop host drops.${DOMAIN}
        handle @neodrop {
            reverse_proxy 192.168.11.90:30081 192.168.11.91:30081 192.168.11.92:30081
        }

        @proxmox host proxmox.${DOMAIN}
        handle @proxmox {
            import auth
            reverse_proxy https://192.168.11.110:8006 {
                transport http {
                    tls_insecure_skip_verify
                }
            }
        }

        @overseerr host overseerr.${DOMAIN}
        handle @overseerr {
            reverse_proxy 192.168.11.90:5055 192.168.11.91:5055 192.168.11.92:5055
        }

        @sonarr host sonarr.${DOMAIN}
        handle @sonarr {
            import auth
            reverse_proxy 192.168.11.90:8989 192.168.11.91:8989 192.168.11.92:8989
        }

        @radarr host radarr.${DOMAIN}
        handle @radarr {
            import auth
            reverse_proxy 192.168.11.90:7878 192.168.11.91:7878 192.168.11.92:7878
        }

        @prowlarr host prowlarr.${DOMAIN}
        handle @prowlarr {
            import auth
            reverse_proxy 192.168.11.90:9696 192.168.11.91:9696 192.168.11.92:9696
        }

        @sabnzbd host sabnzbd.${DOMAIN}
        handle @sabnzbd {
            import auth
            reverse_proxy 192.168.11.90:8080 192.168.11.91:8080 192.168.11.92:8080
        }

        @requestrr host requestrr.${DOMAIN}
        handle @requestrr {
            reverse_proxy 192.168.11.90:4545 192.168.11.91:4545 192.168.11.92:4545
        }

        @paperless host paperless.${DOMAIN}
        handle @paperless {
            import auth
            reverse_proxy 192.168.11.90:8000 192.168.11.91:8000 192.168.11.92:8000
        }

        @wazuh host wazuh.${DOMAIN}
        handle @wazuh {
            import auth
            
            # Custom alerts API gateway (port 55001)
            route /wazuh-api/alerts {
                uri strip_prefix /wazuh-api
                reverse_proxy 192.168.11.57:55001
            }
            
            # API gateway for everything else (port 55000)
            route /wazuh-api/* {
                uri strip_prefix /wazuh-api
                reverse_proxy https://192.168.11.57:55000 {
                    transport http {
                        tls_insecure_skip_verify
                    }
                }
            }

            # Proxmox VE API gateway (with token injection)
            route /pve-api/* {
                uri strip_prefix /pve-api
                reverse_proxy https://192.168.11.110:8006 {
                    header_up Authorization "PVEAPIToken=root@pam!mobile-app=fb3aba52-445d-40b1-b28d-65d7d481a007"
                    transport http {
                        tls_insecure_skip_verify
                    }
                }
            }

            # Prometheus Metrics API gateway
            route /prometheus-api/* {
                uri strip_prefix /prometheus-api
                reverse_proxy 192.168.11.50:9090
            }
            
            # Wazuh Dashboard Web UI
            route {
                reverse_proxy https://192.168.11.57:443 {
                    transport http {
                        tls_insecure_skip_verify
                    }
                }
            }
        }

        # Catch-all fallback
        handle {
            abort
        }
    }
}

# Authelia SSO interface
auth.${DOMAIN} {
    log {
        output file /var/log/caddy/access.log
        format json
    }
    
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    
    route {
        # Apple App Site Association for Passkeys
        handle /.well-known/apple-app-site-association {
            header Content-Type "application/json"
            respond \`{"webcredentials":{"apps":["27H9V537MH.com.secops.mobile.wazuh-ollama-ios"]}}\`
        }

        crowdsec
        reverse_proxy 192.168.11.90:9091 192.168.11.91:9091 192.168.11.92:9091
    }
}

# Root Personal Website Domain
${DOMAIN} {
    log {
        output file /var/log/caddy/access.log
        format json
    }
    
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    
    route {
        crowdsec
        reverse_proxy 192.168.11.80:80
    }
}
EOF
chown caddy:caddy /etc/caddy/Caddyfile
chmod 644 /etc/caddy/Caddyfile

echo "==> Creating systemd service file"
cat > /etc/systemd/system/caddy.service << 'EOF'
[Unit]
Description=Caddy Web Server (Centralized Reverse Proxy)
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
EnvironmentFile=/etc/caddy/caddy.env
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

echo "==> Starting Caddy"
systemctl daemon-reload
systemctl enable caddy
systemctl restart caddy

# ── node_exporter ─────────────────────────────────────────────────────────────
echo "==> Installing node_exporter"
apt-get install -y -qq prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo "==> Caddy installation and deployment complete!"
