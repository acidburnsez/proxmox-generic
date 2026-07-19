# CLAUDE.md — proxmox-personal-production

Infrastructure is composed of LXC containers and a 3-node K3s Kubernetes cluster on a Proxmox VE hypervisor.

## Key facts

- **Proxmox host:** 192.168.1.110 (also reachable via Tailscale at 100.118.22.28)
- **Subnet:** 192.168.11.0/24, gateway 192.168.11.1 (OPNsense)
- **Domain:** example.com (Cloudflare, wildcard cert via DNS-01)
- **Static IP:** 83.217.174.253 (YouFibre, DMZ → OPNsense WAN 192.168.1.148)
- **Tailscale Subnet Router:** proxmox-personal-production-1 (100.107.133.90) is a pod inside K3s and advertises 192.168.11.0/24 and 192.168.1.0/24

## Container & Node Map

| VM ID | Hostname / Service | IP | Type | Service / Function |
|---|---|---|---|---|
| 201 | ergo-irc | 192.168.11.55 | LXC | Ergo IRC (port 6697 TLS, forwarded from WAN) |
| 206 | requestrr | 192.168.11.66 | LXC | Requestrr Discord bot (media requests → Overseerr) |
| 300 | prometheus | 192.168.11.50 | LXC | Prometheus scraper |
| 301 | grafana | 192.168.11.51 | LXC | Grafana dashboards |
| 302 | pve-exporter | 192.168.11.52 | LXC | Proxmox PVE metrics |
| 303 | caddy | 192.168.11.53 | LXC | Caddy reverse proxy + TLS termination |
| 304 | alertmanager | 192.168.11.56 | LXC | Prometheus Alertmanager |
| 308 | vault | 192.168.11.68 | LXC | HashiCorp Vault Server & Token Dispenser (port 8000) |
| 309 | gitea | 192.168.11.69 | LXC | Gitea Git Server & Actions CI/CD Runner |
| 310 | wazuh | 192.168.11.57 | LXC | Wazuh SIEM/XDR Server |
| 700 | k3s-master-01 | 192.168.11.90 | VM | K3s control plane node |
| 701 | k3s-worker-01 | 192.168.11.91 | VM | K3s worker node 01 (RTX 2070 Super GPU) |
| 702 | k3s-worker-02 | 192.168.11.92 | VM | K3s worker node 02 |
| - | authelia | auth.example.com | Pod | Authelia SSO / MFA portal (K3s) |
| - | homepage | homepage.example.com | Pod | Homepage dashboard portal (K3s) |
| - | uptime-kuma | status.example.com | Pod | Uptime Kuma status monitor (K3s) |
| - | ollama | ollama.example.com | Pod | Ollama Local LLM Server (K3s GPU) |
| - | plex | plex.example.com | Pod | Plex Media Server (K3s GPU) |
| - | sabnzbd | sabnzbd.example.com | Pod | SABnzbd Usenet downloader (K3s) |
| - | sonarr | sonarr.example.com | Pod | Sonarr TV automation (K3s) |
| - | radarr | radarr.example.com | Pod | Radarr movie automation (K3s) |
| - | prowlarr | prowlarr.example.com | Pod | Prowlarr indexer manager (K3s) |
| - | overseerr | overseerr.example.com | Pod | Overseerr media request manager (K3s) |
| - | paperless | paperless.example.com | Pod | Paperless-ngx document manager (K3s) |
| - | tailscale | 100.107.133.90 | Pod | Tailscale subnet router (K3s) |
| - | argocd | argocd.example.com | Pod | ArgoCD GitOps engine (K3s) |

## Media storage

A 2TB drive (`/dev/sda`) is mounted on the Proxmox host at `/mnt/media` and bind-mounted into containers 400–404 as `/media`.

Layout inside containers:
```
/media/
  downloads/incomplete/   # SABnzbd temp
  downloads/complete/     # SABnzbd finished
  tv/                     # Sonarr → Plex
  movies/                 # Radarr → Plex
```

Permissions: directories are chowned to UID/GID 100000 on the host (unprivileged container root mapping).

The bind mount is set in each container's `/etc/pve/lxc/<vmid>.conf` as:
```
mp0: /mnt/media,mp=/media
```

## Secrets

**Never commit secrets.** They are stored securely inside **HashiCorp Vault** (VM 308, local IP `192.168.11.68` / Tailscale `100.122.83.102`). 

Workstation authentication to Vault is completely tokenless and passwordless. You retrieve an ephemeral (5-minute) token by passing your Tailscale node identity to the Vault token dispenser sidecar.

Vault KV Path: `secret/proxmox`

## Terraform workflow

Terraform state is stored remotely inside Gitea's native Package Registry. 
The CI/CD pipeline runs automatically via Gitea Actions on Pull Requests (`terraform plan`) and pushes to `main` (`terraform apply`).

For local development:
```bash
cd terraform
export VAULT_TOKEN=$(curl -s http://100.122.83.102:8000/token)
# Initialize remote state backend (replace <GITEA_TOKEN> with Gitea PAT)
terraform init \
  -backend-config="address=https://gitea.example.com/api/packages/user/terraform/state/proxmox" \
  -backend-config="username=user" \
  -backend-config="password=<GITEA_TOKEN>"
terraform plan
terraform apply
```

All scripts are idempotent. Scripts re-run only when their content changes (`filemd5` triggers). Re-running apply is safe.

SSH access to containers uses the Proxmox host as a bastion:
```bash
ssh -J root@192.168.1.110 root@192.168.11.6X
```

## Adding a container

1. Add a module call in a `.tf` file (see existing usenet.tf for the pattern)
2. Add a `null_resource` with a `file` + `remote-exec` provisioner to run an install script
3. Add the install script to `terraform/scripts/`
4. If the container needs media access, add a `null_resource` to append `mp0: /mnt/media,mp=/media` to its LXC config and restart it

VM ID ranges: 200–299 general, 300–399 monitoring, 400–499 media, 500–599 networking.

## Known quirks

- Plex and Ollama containers run in unprivileged mode with udev rules and device mapping on the host for secure GPU passthrough.
- `pct exec` doesn't work well for provisioning in Terraform — always SSH directly to the container IP with the Proxmox host as bastion.
- Nvidia-uvm major device number is `511` on this host (not the commonly documented `234`).
- SABnzbd apt package requires `/etc/default/sabnzbdplus` to exist with `USER`, `HOST`, and `PORT` set — the package does not create it automatically.
- Sonarr/Radarr/Prowlarr are installed from GitHub release tarballs (no apt repo).
- The Tailscale subnet router runs as a pod inside the K3s cluster (namespace tailscale). After first deploy, approve advertised subnet routes (192.168.11.0/24, 192.168.1.0/24) at https://login.tailscale.com/admin/machines.
- OPNsense is on the 192.168.1.0/24 network (WAN-side of the personal production environment), not 192.168.11.0/24. Its LAN interface is 192.168.11.1.
