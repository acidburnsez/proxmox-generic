# proxmox-personal-production

Infrastructure as Code for a Proxmox VE personal production environment. Terraform provisions and configures all LXC containers from scratch — no manual SSH steps required after `terraform apply`.

## Stack

| Service | Type | IP / Access | Details / VM ID |
|---|---|---|---|
| Caddy (reverse proxy & CrowdSec) | LXC | 192.168.11.53 | VM 303 |
| Gitea Git Server | LXC | 192.168.11.69 | VM 203 |
| Wazuh SIEM | LXC | 192.168.11.57 | VM 310 |
| Ergo IRC | LXC | 192.168.11.55 | VM 201 |
| Gotify Alerts | LXC | 192.168.11.58 | VM 307 |
| K3s Master 01 | VM | 192.168.11.90 | VM 100 |
| K3s Worker 01 | VM (Nvidia GPU) | 192.168.11.91 | VM 101 |
| K3s Worker 02 | VM | 192.168.11.92 | VM 102 |
| Authelia SSO | K3s Pod | https://auth.example.com | NodePort 9091 |
| Homepage Dashboard | K3s Pod | https://homepage.example.com | NodePort 3000 |
| Uptime Kuma Status | K3s Pod | https://status.example.com | NodePort 3001 |
| Ollama Local LLM | K3s Pod | https://ollama.example.com | NodePort 11434 (GPU Shared) |
| NeoBear Web IRC | K3s Pod | https://chat.example.com | Ingress / chat |
| NeoDrop File Sharing | K3s Pod | https://drops.example.com | Ingress / drops |
| Tailscale Subnet Router | K3s Pod | 100.107.133.90 | Deployment (Longhorn) |
| Plex | K3s Pod | https://plex.example.com | NodePort 32400 (GPU Shared) |
| SABnzbd | K3s Pod | https://sabnzbd.example.com | NodePort 8080 |
| Sonarr | K3s Pod | https://sonarr.example.com | NodePort 8989 |
| Radarr | K3s Pod | https://radarr.example.com | NodePort 7878 |
| Prowlarr | K3s Pod | https://prowlarr.example.com | NodePort 9696 |
| Overseerr | K3s Pod | https://overseerr.example.com | NodePort 5055 |
| Requestrr | K3s Pod | https://requestrr.example.com | NodePort 4545 |
| Paperless-ngx | K3s Pod | https://paperless.example.com | NodePort 8000 |
| Grafana Dashboards | K3s Pod | https://grafana.example.com | NodePort 30030 |
| Prometheus UI | K3s Pod | https://prometheus.example.com | NodePort 30090 |
| Alertmanager | K3s Pod | NodePort 30093 | Discord Integration |
| SRE Monarch Prober | K3s Pod | CronJob | ConfigMap script |

**Proxmox host:** 192.168.1.110
**Subnet:** 192.168.11.0/24
**Domain:** example.com (Let's Encrypt wildcard cert via Cloudflare DNS-01)

## Services

All HTTP services are available over HTTPS via the Caddy reverse proxy:

| URL | Backend |
|---|---|
| https://homepage.example.com | Homepage Portal dashboard (SSO protected) |
| https://status.example.com | Public Uptime Kuma status monitor |
| https://auth.example.com | Authelia SSO portal |
| https://grafana.example.com | Grafana dashboards |
| https://prometheus.example.com | Prometheus UI |
| https://plex.example.com | Plex Media Server |
| https://proxmox.example.com | Proxmox web UI |
| https://overseerr.example.com | Overseerr media requests |
| https://requestrr.example.com | Requestrr bot admin UI |
| https://wazuh.example.com | Wazuh SIEM Dashboard |
| https://paperless.example.com | Paperless-ngx document manager (SSO protected) |
| https://gitea.example.com | Gitea Git Server & Actions (SSO protected) |
| https://argocd.example.com | ArgoCD GitOps engine (SSO protected) |
| https://gotify.example.com | Gotify Push Alerts Server |
| https://chat.example.com | NeoBear Web IRC Client |
| https://drops.example.com | NeoDrop Encrypted File Sharing |
| irc.example.com:6697 | Ergo IRC (TLS) |

Media stack (LAN/SSO only):

| URL | Service |
|---|---|
| https://sabnzbd.example.com | SABnzbd (downloader) |
| https://sonarr.example.com | Sonarr (TV) |
| https://radarr.example.com | Radarr (movies) |
| https://prowlarr.example.com | Prowlarr (indexers) |
| https://overseerr.example.com | Overseerr (requests) |

Monitoring & General (LAN only):

| URL | Service |
|---|---|
| http://192.168.11.90:30093 | Alertmanager UI (NodePort) |
| https://ollama.example.com | Ollama API |
| http://192.168.11.90:3000 | Homepage Backend (NodePort) |
| http://192.168.11.90:3001 | Uptime Kuma Backend (NodePort) |

## Prerequisites

- Proxmox VE 9.x on Debian Trixie
- Terraform >= 1.5
- SSH agent running with your key loaded (`ssh-add`)
- A Cloudflare account with your domain
- A Tailscale account

### Proxmox API Token

In the Proxmox web UI: **Datacenter → API Tokens → Add**

- User: `root@pam`
- Token ID: `terraform`
- Privilege Separation: **unchecked** (token inherits root permissions)

### Cloudflare API Token

In Cloudflare: **My Profile → API Tokens → Create Token**

- Template: Edit zone DNS
- Zone: `example.com` only

### Tailscale Auth Key

In Tailscale: **Admin → Settings → Keys → Generate auth key**

- Reusable: yes
- Pre-authorized: yes

## Secrets

Secrets are stored securely in **HashiCorp Vault** (VM 308, local IP `192.168.11.68` / Tailscale `100.122.83.102`) at the KV-V2 path `secret/proxmox`.

Authentication from your host Mac is completely tokenless and passwordless, leveraging your **Tailscale network identity** to request an ephemeral (5-minute) token from the local Token Dispenser sidecar.

Non-sensitive variables live in `terraform/terraform.tfvars` (also gitignored):

```hcl
proxmox_endpoint = "https://192.168.1.110:8006/"
proxmox_host     = "192.168.1.110"
default_gateway  = "192.168.11.1"
proxmox_node     = "prox"
```

## Usage

```bash
cd terraform

# Fetch ephemeral Vault access token via Tailscale identity
export VAULT_TOKEN=$(curl -s http://100.122.83.102:8000/token)

# First run — initialise providers and modules
terraform init

# Preview changes
terraform plan

# Apply everything
terraform apply
```

Terraform will:

1. Download the Ubuntu 24.04 LXC template
2. Create all containers with correct networking and SSH access
3. SSH into each container and run the install scripts
4. Issue TLS certificates via Let's Encrypt (Cloudflare DNS-01)
5. Configure Caddy with HTTPS reverse proxies and CrowdSec IPS protection

Re-running `terraform apply` is safe — all scripts are idempotent. Scripts only re-run when their content changes (tracked via `filemd5` triggers).

## DNS Records

Add these in Cloudflare — proxied **OFF** (grey cloud):

| Name | Type | Value |
|---|---|---|
| `*` | A | `192.168.11.53` |
| `irc` | A | `192.168.11.55` |

The wildcard covers homepage, status, auth, grafana, prometheus, plex, and proxmox subdomains via Caddy. IRC connects directly.

## Architecture

```
Internet / Tailscale
  192.168.11.53  ← Caddy Reverse Proxy & CrowdSec IPS (*.example.com)
  ┌──────────────────────────────────────────────┐
  │  homepage.example.com     → k3s-cluster (SSO)   │
  │  status.example.com       → k3s-cluster         │
  │  auth.example.com         → k3s-cluster (SSO)   │
  │  grafana.example.com      → k3s-cluster         │
  │  prometheus.example.com   → k3s-cluster         │
  │  plex.example.com         → k3s-cluster         │
  │  proxmox.example.com      → host:8006           │
  │  overseerr.example.com    → k3s-cluster         │
  │  requestrr.example.com    → k3s-cluster         │
  │  paperless.example.com    → k3s-cluster (SSO)   │
  │  gitea.example.com        → .69:3000 (SSO)      │
  │  gotify.example.com       → .58:80              │
  │  chat.example.com         → k3s-cluster         │
  │  drops.example.com        → k3s-cluster         │
  │  argocd.example.com       → k3s-cluster (SSO)   │
  └──────────────────────────────────────────────┘

  192.168.11.55  ← Ergo IRC (irc.example.com:6697, TLS)
  192.168.11.54  ← Tailscale (subnet router, exposes 192.168.11.0/24)
  192.168.11.57  ← Wazuh SIEM (security monitoring & alerting)
  192.168.11.58  ← Gotify Alerts (unprivileged LXC container)
  192.168.11.68  ← HashiCorp Vault (Secrets storage & Tailscale Token Dispenser)
  192.168.11.69  ← Gitea Git Server & Actions CI/CD Runner
  192.168.11.90  ← K3s Master 01 (Kubernetes control plane)
  192.168.11.91  ← K3s Worker 01 (Kubernetes compute node + Nvidia GPU)
  192.168.11.92  ← K3s Worker 02 (Kubernetes compute node)
```

### Plex & Ollama — Unprivileged GPU Passthrough

Plex and Ollama run in **unprivileged** LXC containers with Nvidia RTX 2070 Super passthrough. This requires special handling:

- Filesystem directories are shifted by `100000` via a Python shifter script walk on mount to align files to the unprivileged container subuid range.
- Host device permissions are set to `0666` via persistent udev rules (`/etc/udev/rules.d/70-nvidia.rules`).
- GPU device nodes are mounted via config entry parameters directly into the unprivileged namespaces.
- Nvidia driver 595.80 installed via runfile with `--no-kernel-modules` (shares the host kernel module)
- cgroup2 device rules for major numbers: 195 (nvidia), 511 (nvidia-uvm), 226 (nvidia-modeset)

### TLS Certificates

Wildcard cert `*.example.com` is issued on the Nginx container via `acme.sh` + Cloudflare DNS-01. A separate cert for `irc.example.com` is issued on the IRC container. Both auto-renew via cron.

### Tailscale

The Tailscale container acts as a subnet router advertising `192.168.11.0/24` to your tailnet. After first apply, approve the route at:
https://login.tailscale.com/admin/machines → proxmox-personal-production → Edit route settings

To restrict friends to IRC only, assign `tag:irc-user` to their device in the Tailscale admin panel and apply this ACL policy:

```json
{
  "tagOwners": { "tag:irc-user": ["autogroup:admin"] },
  "acls": [
    { "action": "accept", "src": ["autogroup:admin"], "dst": ["*:*"] },
    { "action": "accept", "src": ["tag:irc-user"], "dst": ["192.168.11.55:6667", "192.168.11.55:6697"] }
  ]
}
```

### Media Request Pipeline

Full flow from request to playback:

```
Discord /request → Requestrr (CT 206)
                       │
                       ▼
              Overseerr (CT 405) ──── Plex library sync
                  │         │
                  ▼         ▼
            Sonarr        Radarr
            (CT 402)      (CT 403)
                  │         │
                  └────┬────┘
                       ▼
                  SABnzbd (CT 401)
                       │
                       ▼
               /media/downloads/
                       │
                  auto-import
                       │
              /media/tv  /media/movies
                       │
                       ▼
                  Plex (CT 400)
```

**Requestrr** is a Discord bot — users type `/request` in Discord and it routes to Overseerr. Configure it at https://requestrr.example.com (Movies and TV Shows tabs → set client to Overseerr, host `192.168.11.65`, port `5055`).

After first deploy, enable Plex libraries in Overseerr via the API:
```bash
curl "https://overseerr.example.com/api/v1/settings/plex/library?enable=1,2" \
  -H "X-Api-Key: <overseerr-api-key>"
```

### Wazuh SIEM & Security

Wazuh SIEM/XDR (CT 310) provides centralized security monitoring, host intrusion detection, and log auditing across the entire production stack.

- **Storage Mount**: Configured with a dedicated LVM mount `/dev/sdb` bind-mounted to `/var/ossec` for high-volume logs, indexers, and alerts.
- **Zero-Swap Configuration**: The container runs with `swap = 0` (`swap_mb = 0` in Terraform) to prevent OpenSearch from swapping memory pages to disk, preventing heavy disk thrashing and optimizing SIEM database speed.
- **Centralized Agent Fleet Rollout**: Managed via [install-agents-fleet.sh](file:///home/user/dev/proxmox/terraform/scripts/install-agents-fleet.sh). The script runs once on the host, downloads the agent deb package, and leverages Proxmox `pct push` / `pct exec` to copy and install/configure the agent on all running LXC containers in parallel (solving outbound firewall blocks).
- **Proxmox VE Host Monitoring**: Configures `rsyslog` on the host to mirror binary systemd `journald` events to standard text-based files (`/var/log/auth.log` and `/var/log/syslog`) in real time, which the Wazuh agent actively tails.
- **OPNsense Integration**: Remote syslog ingestion is active over UDP port 514, streaming edge firewall connection and Suricata IPS logs directly to the SIEM (allowed in `firewall.tf`).
- **Discord Real-time Alerts**: A custom python integration alerts on security threats (Level >= 5 by default, including brute-force attempts, invalid SSH user logins, or privilege escalations) directly to the **#security-alerts** Discord channel.

### Ollama & Local AI Security Analyst

Ollama runs in a dedicated container (CT 311) on IP `192.168.11.58` and operates as an autonomous, private, offline security analyst.

- **GPU Passthrough**: Configured in **privileged** mode (`unprivileged: 0`) with Nvidia RTX 2070 Super GPU passthrough enabled (sharing the card dynamically with Plex). Includes CUDA userspace libraries matching the host driver version (`595.80`).
- **Llama 3 Model**: Pulls and hosts the `llama3:8b` model locally. Exposes API queries internally on port `11434`.
- **Wazuh Security Summarizer**: A python script (`wazuh-summary.py` in CT 310) runs as a daily cron job at 8:00 PM. It aggregates logs from the last 24 hours, injects an Environment Architecture Map of the personal production stack for high-fidelity context, queries the local Ollama container, and posts a color-coded security digest with threat analysis and 3 specific remediation steps directly into the **#security-summary** Discord channel.
- **On-Demand Summary CLI**: Running the `/usr/local/bin/wazuh-summary` command on the Proxmox host immediately compiles the last 24 hours of logs, queries Ollama, and sends the AI-assisted security brief to Discord on-demand.


### Discord Notifications

All alerts and media events route to a single Discord webhook (`TF_VAR_alertmanager_discord_webhook` in `secrets.env`):

| Source | Events |
|---|---|
| Alertmanager | Instance down, disk space low, high memory |
| Sonarr | Episode grabbed, downloaded, imported |
| Radarr | Movie grabbed, downloaded |
| Overseerr | Request pending, approved, available, failed |

Sonarr/Radarr notifications are configured via their respective APIs on first deploy. Overseerr notifications via `POST /api/v1/settings/notifications/discord`.

### Firewall Isolation

Every container has a Proxmox firewall policy (`input_policy=DROP`, `output_policy=ACCEPT`) with explicit ACCEPT rules. Outbound rules allow only the specific IPs each container legitimately needs to reach — e.g. Requestrr can only reach Overseerr on the LAN; everything else is REJECTed before the default ACCEPT. All rules are defined in `terraform/firewall.tf`.

### IRC

Ergo v2.18.0 — private IRC server with user accounts, nick reservation, and persistent history. The IRC container has Proxmox firewall rules blocking outbound connections to the rest of the LAN (pivot prevention).

After connecting, register your nick:

```
/msg NickServ REGISTER <password> <email>
```

WeeChat setup:

```
/server add home irc.example.com/6697 -tls
/set irc.server.home.sasl_mechanism plain
/set irc.server.home.sasl_username <nick>
/set irc.server.home.sasl_password <password>
/connect home
```

## Adding a New Container

1. Add a module call in a new or existing `.tf` file:

```hcl
module "myservice" {
  source = "./modules/lxc"

  vm_id       = 202   # pick a free ID from your range
  hostname    = "myservice"
  node_name   = var.proxmox_node

  template_file_id = proxmox_download_file.ubuntu_2404_lxc.id

  storage   = var.default_storage
  disk_size = 8
  cpu_cores = 1
  memory_mb = 512

  ip_address = "192.168.11.XX/24"
  gateway    = var.default_gateway
  bridge     = var.default_bridge

  ssh_public_key = var.ssh_public_key
  tags           = ["terraform", "myservice"]
}
```

2. Add a `null_resource` to SSH directly into the container and run your install script
3. Add your install script to `terraform/scripts/`

## VM ID Ranges

| Range | Purpose |
|---|---|
| 200–299 | General purpose |
| 300–399 | Monitoring / metrics |
| 400–499 | Media |
| 500–599 | Networking / proxy |

## Repo Structure

```
terraform/
├── main.tf              # Provider config (bpg/proxmox pinned to 0.110.0)
├── variables.tf         # All input variables
├── templates.tf         # Ubuntu 24.04 LXC template download
├── network.tf           # Bridge / VLAN definitions
├── containers.tf        # VM ID range documentation
├── monitoring.tf        # Prometheus + Grafana
├── pve-exporter.tf      # Proxmox PVE exporter
├── caddy.tf             # Caddy reverse proxy + Cloudflare SSL
├── authelia.tf          # Authelia SSO Portal config
├── backups.tf           # Daily snapshot backups cron job
├── gitea.tf             # Gitea Git Server setup
├── homepage.tf          # Homepage dashboard setup
├── uptime-kuma.tf       # Uptime Kuma monitoring VM
├── plex.tf              # Plex + Nvidia GPU passthrough
├── usenet.tf            # SABnzbd, Sonarr, Radarr, Prowlarr
├── tailscale.tf         # Tailscale subnet router
├── irc.tf               # Ergo IRC + firewall isolation
├── overseerr.tf         # Overseerr media request manager
├── requestrr.tf         # Requestrr Discord bot
├── vault.tf             # HashiCorp Vault server + Token Dispenser setup
├── firewall.tf          # Per-container Proxmox firewall rules
├── modules/
│   └── lxc/             # Reusable LXC container module
└── scripts/
    ├── install-monitoring.sh
    ├── install-pve-exporter.sh
    ├── install-caddy.sh
    ├── install-authelia.sh
    ├── install-gitea.sh
    ├── install-homepage.sh
    ├── install-uptime-kuma.sh
    ├── install-plex.sh
    ├── install-tailscale.sh
    ├── install-ergo.sh
    ├── install-irc-tls.sh
    ├── install-sabnzbd.sh
    ├── install-sonarr.sh
    ├── install-radarr.sh
    ├── install-prowlarr.sh
    ├── install-overseerr.sh
    ├── install-vault.sh
    ├── vault-token-dispenser.py
    └── install-requestrr.sh
```

## Known Quirks

- `pct exec` returns exit 127 in Terraform's non-interactive SSH context for script execution. Workaround: SSH directly to the container IP in the `connection` block.
- The Proxmox API token cannot modify `features` on a privileged container — both `unprivileged` and `features` are in `lifecycle { ignore_changes }` on the Plex resource.
- Nvidia-uvm major device number is `511` on this host (not the commonly documented `234`).
- acme.sh install syntax: use `sh -s email="..."` not `sh -s -- --accountemail`.
- SABnzbd runs as root and defaults to creating completed download folders as `root:root 700`. Radarr/Sonarr (uid 999) can't read them. Fix: set `permissions = "0755"` in `/root/.sabnzbd/sabnzbd.ini` and restart SABnzbd. This is pre-configured in `install-sabnzbd.sh` but may need manual correction if the container was provisioned before the fix.
- Radarr has a "BR Disc" custom format (score −9999 on all quality profiles) that blocks Blu-ray ISO/disc releases. Without it, Radarr will happily grab full-disc ISOs that it can't import. The custom format matches: `Blu-ray` (without `REMUX`), `BDMV`, `COMPLETE.BLURAY`, `@HDSpace`. This is a live Radarr config change — not in Terraform. If the container is rebuilt, re-create it via Radarr Settings → Custom Formats.
- Plex remote access requires port 32400 forwarded from WAN (OPNsense NAT) and `customConnections` set to the `plex.direct` HTTPS URL format: `https://WAN-IP-DASHES.MACHINE_UUID.plex.direct:32400`. Plain `http://IP:32400` is silently ignored by plex.tv. NAT reflection must be enabled on the OPNsense port forward rule so the server can validate its own external address.

### Gitea Git Server & Actions (CI/CD)

Gitea (CT 309) operates as the central homelab repository host on IP `192.168.11.69` and includes a built-in CI/CD engine compatible with GitHub Actions.

- **Act Runner Integration**: Launches the `gitea/act_runner` container in Docker-in-Docker mode, mounting the host's `/var/run/docker.sock` to execute build steps inside container sandboxes.
- **Vulnerability Audits**: Integrated with `trivy` container scanning. Audits run weekly via cron and stream logs straight to the Wazuh agent in JSON format, triggering security alerts on the Wazuh SIEM dashboard.
- **OIDC Single Sign-On**: Registered as a client in Authelia (`install-authelia.sh`), enabling passwordless "Sign in with Authelia" for users.
