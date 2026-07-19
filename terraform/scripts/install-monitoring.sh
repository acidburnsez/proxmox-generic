#!/usr/bin/env bash
# Run this script INSIDE each container after terraform apply.
#
# On Prometheus:  ssh root@192.168.11.50  then run this script
# On Grafana:     ssh root@192.168.11.51  then run this script
#
# Or run remotely:
#   ssh root@192.168.11.50 "bash -s prometheus" < install-monitoring.sh
#   ssh root@192.168.11.51 "bash -s grafana"    < install-monitoring.sh

set -euo pipefail

ROLE="${1:-}"
K3S_TOKEN="${2:-}"

install_prometheus() {
  local k3s_token="${1:-}"
  echo "==> Installing Prometheus"
  apt-get update -qq
  apt-get install -y prometheus

  if [ -n "$k3s_token" ]; then
    echo "==> Configuring K3s scrape token"
    echo "$k3s_token" > /etc/prometheus/k3s-token
    chmod 600 /etc/prometheus/k3s-token
  fi

  cat > /etc/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['192.168.11.56:9093']

rule_files:
  - /etc/prometheus/alerts.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'alertmanager'
    static_configs:
      - targets: ['192.168.11.56:9093']

  - job_name: 'node'
    static_configs:
      - targets:
        - '192.168.11.50:9100'   # prometheus
        - '192.168.11.51:9100'   # grafana
        - '192.168.11.52:9100'   # pve-exporter
        - '192.168.11.53:9100'   # caddy
        - '192.168.11.56:9100'   # alertmanager
        - '192.168.11.80:9100'   # personal-website
        - '192.168.11.90:9100'   # k3s-master-01
        - '192.168.11.91:9100'   # k3s-worker-01
        - '192.168.11.92:9100'   # k3s-worker-02

  - job_name: 'uptime-kuma'
    metrics_path: /metrics
    static_configs:
      - targets: ['192.168.11.90:3001', '192.168.11.91:3001', '192.168.11.92:3001']

  - job_name: 'pve'
    metrics_path: /pve
    params:
      module: [default]
      target: ['192.168.11.110']
    static_configs:
      - targets: ['192.168.11.52:9221']

  - job_name: 'k3s-kubelet'
    scheme: https
    tls_config:
      insecure_skip_verify: true
    authorization:
      credentials_file: /etc/prometheus/k3s-token
    static_configs:
      - targets:
        - '192.168.11.90:10250'
        - '192.168.11.91:10250'
        - '192.168.11.92:10250'

  - job_name: 'k3s-cadvisor'
    scheme: https
    metrics_path: /metrics/cadvisor
    tls_config:
      insecure_skip_verify: true
    authorization:
      credentials_file: /etc/prometheus/k3s-token
    static_configs:
      - targets:
        - '192.168.11.90:10250'
        - '192.168.11.91:10250'
        - '192.168.11.92:10250'
EOF

  cat > /etc/prometheus/alerts.yml <<'EOF'
groups:
  - name: personal-production
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.instance }} is down"
          description: "{{ $labels.instance }} has been unreachable for more than 2 minutes"

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "Root filesystem above 85% full"

      - alert: MediaDiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/media"} / node_filesystem_size_bytes{mountpoint="/media"}) < 0.10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Media drive almost full ({{ $labels.instance }})"
          description: "Less than 10% free on /media — downloads may fail"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory on {{ $labels.instance }}"
          description: "Memory usage above 90%"
EOF

  mkdir -p /etc/systemd/system/prometheus.service.d/
  printf '[Service]\nPrivateUsers=no\n' > /etc/systemd/system/prometheus.service.d/override.conf

  systemctl daemon-reload
  systemctl enable prometheus
  systemctl restart prometheus
  echo "==> Prometheus running on :9090"
}

install_alertmanager() {
  local discord_webhook="${2:-}"

  echo "==> Installing Alertmanager"
  apt-get update -qq
  apt-get install -y prometheus-alertmanager

  if [ -n "$discord_webhook" ]; then
    echo "==> Configuring Discord receiver"
    cat > /etc/prometheus/alertmanager.yml << EOF
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'instance']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'discord'

receivers:
  - name: 'discord'
    discord_configs:
      - webhook_url: '${discord_webhook}'
        send_resolved: true
        title: '{{ if eq .Status "firing" }}🔥{{ else }}✅{{ end }} {{ .CommonLabels.alertname }}'
        message: |
          {{ range .Alerts }}
          **{{ .Labels.instance }}** — {{ .Annotations.summary }}
          {{ .Annotations.description }}
          {{ end }}
EOF
  else
    cat > /etc/prometheus/alertmanager.yml <<'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'instance']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'null'

receivers:
  - name: 'null'
EOF
  fi

  systemctl enable prometheus-alertmanager
  systemctl restart prometheus-alertmanager
  echo "==> Alertmanager running on :9093"
}

install_node_exporter() {
  echo "==> Installing node_exporter"
  apt-get update -qq
  apt-get install -y prometheus-node-exporter
  systemctl enable prometheus-node-exporter
  systemctl restart prometheus-node-exporter
  echo "==> node_exporter running on :9100"
}

install_grafana() {
  echo "==> Installing Grafana"
  apt-get update -qq
  apt-get install -y apt-transport-https software-properties-common wget curl

  wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /usr/share/keyrings/grafana.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
    > /etc/apt/sources.list.d/grafana.list

  apt-get update -qq
  apt-get install -y grafana

  echo "==> Configuring Authelia Auth Proxy in grafana.ini"
  python3 -c '
with open("/etc/grafana/grafana.ini", "r") as f:
    lines = f.readlines()
new_lines = []
in_auth_proxy = False
for line in lines:
    if line.strip() == "[auth.proxy]":
        in_auth_proxy = True
        new_lines.append(line)
        continue
    elif line.strip().startswith("[") and in_auth_proxy:
        in_auth_proxy = False
    if in_auth_proxy:
        if line.strip().startswith(";enabled") or line.strip().startswith("enabled"):
            new_lines.append("enabled = true\n")
        elif line.strip().startswith(";header_name") or line.strip().startswith("header_name"):
            new_lines.append("header_name = Remote-User\n")
        elif line.strip().startswith(";header_property") or line.strip().startswith("header_property"):
            new_lines.append("header_property = username\n")
        elif line.strip().startswith(";auto_sign_up") or line.strip().startswith("auto_sign_up"):
            new_lines.append("auto_sign_up = true\n")
        elif line.strip().startswith(";whitelist") or line.strip().startswith("whitelist"):
            new_lines.append("whitelist = 192.168.11.53\n")
        else:
            new_lines.append(line)
    else:
        new_lines.append(line)
text = "".join(new_lines)
text = text.replace(";auto_assign_org_role = Viewer", "auto_assign_org_role = Admin")
text = text.replace("auto_assign_org_role = Viewer", "auto_assign_org_role = Admin")
with open("/etc/grafana/grafana.ini", "w") as f:
    f.write(text)
'

  # Pre-configure Prometheus as a datasource
  mkdir -p /etc/grafana/provisioning/datasources
  cat > /etc/grafana/provisioning/datasources/prometheus.yml <<'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://192.168.11.50:9090   # update if you changed the Prometheus IP
    isDefault: true
    editable: true
EOF

  # Configure dashboard provider
  mkdir -p /etc/grafana/provisioning/dashboards
  cat > /etc/grafana/provisioning/dashboards/dashboards.yaml <<'EOF'
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: ''
    folderUid: ''
    type: file
    options:
      path: /var/lib/grafana/dashboards
EOF
  rm -f /etc/grafana/provisioning/dashboards/all.yml
  rm -f /etc/grafana/provisioning/dashboards/all.yaml

  # Download and configure default dashboards
  mkdir -p /var/lib/grafana/dashboards
  echo "==> Downloading default dashboards"
  curl -sLo /var/lib/grafana/dashboards/node-exporter.json "https://grafana.com/api/dashboards/1860/revisions/37/download"
  curl -sLo /var/lib/grafana/dashboards/uptime-kuma.json "https://grafana.com/api/dashboards/14191/revisions/1/download"
  curl -sLo /var/lib/grafana/dashboards/proxmox.json "https://grafana.com/api/dashboards/10347/revisions/2/download"
  curl -sLo /var/lib/grafana/dashboards/k3s-cluster.json "https://grafana.com/api/dashboards/15282/revisions/1/download"

  # Align datasource inputs with our datasource name "Prometheus"
  sed -i 's/\${DS_PROMETHEUS}/Prometheus/g' /var/lib/grafana/dashboards/*.json || true
  sed -i 's/"datasource": null/"datasource": "Prometheus"/g' /var/lib/grafana/dashboards/*.json || true
  chown -R grafana:grafana /var/lib/grafana/dashboards

  systemctl enable grafana-server
  systemctl restart grafana-server
  echo "==> Grafana running on :3000  (login: admin / admin)"
}

case "$ROLE" in
  prometheus)
    install_prometheus "$K3S_TOKEN"
    install_node_exporter
    ;;
  grafana)
    install_grafana
    install_node_exporter
    ;;
  alertmanager)
    install_alertmanager
    install_node_exporter
    ;;
  *)
    echo "Usage: $0 [prometheus|grafana|alertmanager]"
    exit 1
    ;;
esac
