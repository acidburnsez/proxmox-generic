#!/usr/bin/env bash
# Installs Wazuh SIEM All-in-One on Ubuntu 24.04.
# Called by Terraform null_resource — do not run manually.

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive

DISCORD_WEBHOOK="${1:-}"
GOTIFY_TOKEN="${2:-}"

# ── 1. Install Wazuh Packages if not present ──────────────────────────────────
if ! { dpkg -s wazuh-manager >/dev/null 2>&1 && dpkg -s wazuh-indexer >/dev/null 2>&1; }; then
  echo "==> Installing dependencies"
  apt-get update -qq
  apt-get install -y -qq curl apt-transport-https lsb-release gnupg2 ca-certificates dbus tar unzip rsyslog

  echo "==> Downloading Wazuh installation assistant"
  curl -sO https://packages.wazuh.com/4.8/wazuh-install.sh

  # Determine if we need to pass --overwrite (e.g. empty mount directories exist)
  EXTRA_ARGS=""
  if [ -d "/var/ossec" ] || [ -d "/var/lib/wazuh-indexer" ]; then
    echo "==> Empty mount point directories detected. Adding --overwrite to installation arguments."
    EXTRA_ARGS="-o"
  fi

  echo "==> Running Wazuh all-in-one installation"
  # We pipe output to a log file to prevent screen spam
  bash wazuh-install.sh -a $EXTRA_ARGS > /var/log/wazuh-install.log 2>&1 || {
    echo "Wazuh installation failed! Checking last 50 lines of logs:"
    tail -n 50 /var/log/wazuh-install.log
    exit 1
  }

  echo "==> Extracting generated passwords"
  if [ -f wazuh-install-files.tar ]; then
    tar -O -xf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt > /root/wazuh-passwords.txt || true
    chmod 600 /root/wazuh-passwords.txt
  fi
else
  echo "==> Wazuh packages already present. Skipping base installation."
fi

# ── 2. Configure Discord Integration if Webhook is provided ───────────────────
if [ -n "${DISCORD_WEBHOOK}" ]; then
  echo "==> Configuring Discord alerting integration"
  
  # Create custom-discord launcher
  cat > /var/ossec/integrations/custom-discord << 'EOF'
#!/bin/sh
export SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"
WPYTHON_BIN="/var/ossec/framework/python/bin/python3"
DIR=$(dirname "$0")
$WPYTHON_BIN $DIR/custom-discord.py "$1" "$2"
EOF

  # Create custom-discord python script
  cat > /var/ossec/integrations/custom-discord.py << 'EOF'
#!/var/ossec/framework/python/bin/python3
import sys
import json
import urllib.request
import ssl
import os
import time

alert_file = sys.argv[1]
hook_url = sys.argv[2]

with open(alert_file, 'r') as f:
    alert_json = json.loads(f.read())

level = alert_json.get('rule', {}).get('level', 0)
description = alert_json.get('rule', {}).get('description', 'No description')
agent_name = alert_json.get('agent', {}).get('name', 'manager')
agent_id = alert_json.get('agent', {}).get('id', '000')
location = alert_json.get('location', 'unknown')

# Only alert on level >= 5 (standard warning alert threshold)
if level < 5:
    sys.exit(0)

color = 15158332 # Red
if level < 7:
    color = 3066993 # Green
elif level < 10:
    color = 16776960 # Yellow
elif level < 13:
    color = 16744448 # Orange

# Rate limiter config for local Ollama LLM (runs within chroot)
RATE_LIMIT_FILE = "/tmp/ollama_rate_limit.json"
MAX_REQUESTS = 3
WINDOW_SECONDS = 60

def check_rate_limit():
    now = time.time()
    try:
        timestamps = []
        if os.path.exists(RATE_LIMIT_FILE):
            with open(RATE_LIMIT_FILE, 'r') as rf:
                timestamps = json.load(rf)
        
        # Filter timestamps within the moving window
        timestamps = [ts for ts in timestamps if now - ts < WINDOW_SECONDS]
        
        if len(timestamps) >= MAX_REQUESTS:
            return True
            
        timestamps.append(now)
        with open(RATE_LIMIT_FILE, 'w') as wf:
            json.dump(timestamps, wf)
        return False
    except Exception:
        # Fallback to no rate limit if file IO errors occur
        return False

# Query local Ollama LLM for instant security context
ai_context = ""
if check_rate_limit():
    ai_context = "⚠️ *Ollama AI analysis skipped: rate limit exceeded (max 3 queries per minute) to prevent resource exhaustion.*"
else:
    try:
        system_context = (
            "Environment Architecture Map:\n"
            " - Hypervisor: Proxmox VE host (name: 'prox', IPs: 192.168.11.110 / 192.168.1.110)\n"
            " - Firewall: OPNsense VM (VMID 600, IP: 192.168.11.1)\n"
            " - Reverse Proxy: Caddy LXC (CT 303, IP: 192.168.11.53), handles *.example.com reverse proxying with LAN/Tailscale IP restrictions for management consoles (Proxmox/Wazuh).\n"
            " - VPN/Gateway: Tailscale LXC (CT 500, IP: 192.168.11.54) acting as a subnet router.\n"
            " - Wazuh SIEM: Wazuh LXC (CT 310, IP: 192.168.11.57), collects syslog/agent logs from all containers and the host.\n"
            " - Usenet Stack: SABnzbd (CT 401), Sonarr (CT 402), Radarr (CT 403), Prowlarr (CT 404), Overseerr (CT 405)\n"
            " - Media Stack: Plex Media Server (CT 400, privileged with GPU passthrough)\n"
            " - Monitoring: Prometheus (CT 300), Grafana (CT 301), Alertmanager (CT 304), PVE Exporter (CT 302)\n"
            " - Communication: Ergo-IRC (CT 201), Requestrr (CT 206)\n\n"
        )

        ollama_payload = {
            "model": "llama3.2:1b",
            "prompt": (
                "You are a senior security engineer monitoring a personal production environment. "
                "Use the provided Environment Architecture Map to contextualize the alert.\n\n"
                f"{system_context}"
                "Analyze this single security alert and explain its potential security impact in 1 or 2 short sentences. "
                "Suggest exactly 1 immediate verification or containment action. Keep the output extremely concise and return only the requested analysis and action, no chit-chat.\n\n"
                f"Alert Details:\n"
                f"Rule Level: {level}\n"
                f"Rule Description: {description}\n"
                f"Agent Name: {agent_name}\n"
                f"Location: {location}\n"
                f"Full Alert JSON: {json.dumps(alert_json)}\n"
            ),
            "stream": False,
            "options": {
                "temperature": 0.2
            }
        }
        
        req_ollama = urllib.request.Request(
            "http://192.168.11.90:11434/api/generate",
            data=json.dumps(ollama_payload).encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )
        
        # Run with a 12-second timeout to avoid blocking Wazuh's queue
        # HTTP request does not need SSL verification context
        with urllib.request.urlopen(req_ollama, timeout=12) as resp_ollama:
            ollama_data = json.loads(resp_ollama.read().decode('utf-8'))
            ai_context = ollama_data.get("response", "").strip()
    except Exception as e:
        ai_context = f"⚠️ *Ollama AI analysis could not be generated: {e}*"

fields = [
    {"name": "Agent", "value": f"{agent_name} ({agent_id})", "inline": True},
    {"name": "Location", "value": location, "inline": True}
]

if ai_context:
    fields.append({"name": "🤖 AI Security Analyst Context", "value": ai_context, "inline": False})

payload = {
    "embeds": [{
        "title": f"Wazuh Alert - Level {level}",
        "description": description,
        "color": color,
        "fields": fields,
        "footer": {
            "text": "Wazuh SIEM personal production"
        }
    }]
}

req = urllib.request.Request(
    hook_url,
    data=json.dumps(payload).encode('utf-8'),
    headers={
        'Content-Type': 'application/json',
        'User-Agent': 'Wazuh-Integration'
    }
)

try:
    # Use standard CA certificate verification from chroot's cert store
    context = ssl.create_default_context(cafile="/etc/ssl/certs/ca-certificates.crt")
    with urllib.request.urlopen(req, context=context) as response:
        sys.exit(0)
except Exception as e:
    sys.stderr.write(f"Error sending alert to Discord: {e}\n")
    sys.exit(1)
EOF

  # Set permissions
  chmod 750 /var/ossec/integrations/custom-discord*
  chown root:wazuh /var/ossec/integrations/custom-discord*

  # Add integration block to ossec.conf if it does not exist yet
  CONFIG="/var/ossec/etc/ossec.conf"
  if ! grep -q "custom-discord" "$CONFIG"; then
    echo "Appending Discord integration to $CONFIG"
    # Insert before the last </ossec_config>
    sed -i "s|.*</ossec_config>.*|<integration>\n    <name>custom-discord</name>\n    <api_key>${DISCORD_WEBHOOK}</api_key>\n    <alert_format>json</alert_format>\n  </integration>\n</ossec_config>|" "$CONFIG"
  else
    echo "Discord integration already configured in $CONFIG. Ensuring api_key is used and updating webhook."
    python3 -c "
import re
with open('$CONFIG', 'r') as f:
    content = f.read()
# Replace any legacy hook_url tags with api_key
pattern = r'(<integration>\s*<name>custom-discord</name>\s*<)hook_url(>)(.*?)(</)hook_url(>)'
replacement = r'\g<1>api_key\g<2>\g<3>\g<4>api_key\g<5>'
content = re.sub(pattern, replacement, content, flags=re.DOTALL)
# Update api_key value
pattern2 = r'(<integration>\s*<name>custom-discord</name>\s*<api_key>)(.*?)(</api_key>)'
replacement2 = r'\g<1>${DISCORD_WEBHOOK}\g<3>'
content = re.sub(pattern2, replacement2, content, flags=re.DOTALL)
with open('$CONFIG', 'w') as f:
    f.write(content)
"
  fi

  # ── Gotify Integration ────────────────────────────────────────────────────────
  if [ -n "${GOTIFY_TOKEN}" ]; then
    echo "==> Configuring Gotify alerting integration"

    # Create custom-gotify launcher
    cat > /var/ossec/integrations/custom-gotify << 'EOF'
#!/bin/sh
export SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"
WPYTHON_BIN="/var/ossec/framework/python/bin/python3"
DIR=$(dirname "$0")
$WPYTHON_BIN $DIR/custom-gotify.py "$1" "$2"
EOF

    # Create custom-gotify python script
    cat > /var/ossec/integrations/custom-gotify.py << 'EOF'
#!/var/ossec/framework/python/bin/python3
import sys
import json
import urllib.request
import ssl
import os
import time

alert_file = sys.argv[1]
gotify_token = sys.argv[2]
gotify_url = "https://gotify.example.com/message?token=" + gotify_token

with open(alert_file, 'r') as f:
    alert_json = json.loads(f.read())

level = alert_json.get('rule', {}).get('level', 0)
description = alert_json.get('rule', {}).get('description', 'No description')
agent_name = alert_json.get('agent', {}).get('name', 'manager')
agent_id = alert_json.get('agent', {}).get('id', '000')
location = alert_json.get('location', 'unknown')

# 🛠️ Check for active deployment/maintenance window suppression
maintenance_file = "/var/ossec/etc/maintenance_until"
if os.path.exists(maintenance_file) and level < 14:
    try:
        with open(maintenance_file, 'r') as mf:
            until = int(mf.read().strip())
        if time.time() < until:
            sys.exit(0)  # Suppress alerts during maintenance (unless critical level >= 14)
    except Exception:
        pass

# Only page on level >= 10 (Critical alerts)
if level < 10:
    sys.exit(0)

priority = 8
if level >= 13:
    priority = 10

# Query local Ollama LLM for instant security context
ai_context = ""
try:
    system_context = (
        "Environment Architecture Map:\n"
        " - Hypervisor: Proxmox VE host (name: 'prox', IPs: 192.168.11.110 / 192.168.1.110)\n"
        " - Firewall: OPNsense VM (VMID 600, IP: 192.168.11.1)\n"
        " - Reverse Proxy: Caddy LXC (CT 303, IP: 192.168.11.53)\n"
        " - Wazuh SIEM: Wazuh LXC (CT 310, IP: 192.168.11.57)\n\n"
    )

    ollama_payload = {
        "model": "llama3.2:1b",
        "prompt": (
            "You are a senior security engineer. Analyze this alert and explain its potential security impact in 1 short sentence. "
            "Suggest exactly 1 immediate action. Be extremely concise.\n\n"
            f"{system_context}"
            f"Alert Details:\n"
            f"Rule Level: {level}\n"
            f"Rule Description: {description}\n"
            f"Agent Name: {agent_name}\n"
            f"Location: {location}\n"
        ),
        "stream": False,
        "options": {"temperature": 0.2}
    }
    
    req_ollama = urllib.request.Request(
        "http://192.168.11.90:11434/api/generate",
        data=json.dumps(ollama_payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    with urllib.request.urlopen(req_ollama, timeout=12) as resp_ollama:
        ollama_data = json.loads(resp_ollama.read().decode('utf-8'))
        ai_context = ollama_data.get("response", "").strip()
except Exception as e:
    ai_context = f"AI analysis skipped: {e}"

# Format message body
message = (
    f"🚨 Description: {description}\n"
    f"Severity: Level {level}\n"
    f"👤 Agent: {agent_name} ({agent_id})\n"
    f"📍 Location: {location}\n\n"
    f"🤖 AI Assessment:\n{ai_context}"
)

payload = {
    "title": f"Wazuh Alert - Level {level}",
    "message": message,
    "priority": priority,
    "extras": {
        "client::notification": {
            "click": {
                "url": "app://secops/wazuh/alert"
            }
        }
    }
}

req = urllib.request.Request(
    gotify_url,
    data=json.dumps(payload).encode('utf-8'),
    headers={'Content-Type': 'application/json'}
)

try:
    context = ssl.create_default_context(cafile="/etc/ssl/certs/ca-certificates.crt")
    with urllib.request.urlopen(req, context=context) as response:
        sys.exit(0)
except Exception as e:
    sys.stderr.write(f"Error sending alert to Gotify: {e}\n")
    sys.exit(1)
EOF

    # Set permissions
    chmod 750 /var/ossec/integrations/custom-gotify*
    chown root:wazuh /var/ossec/integrations/custom-gotify*

    # Add integration block to ossec.conf if it does not exist yet
    CONFIG="/var/ossec/etc/ossec.conf"
    if ! grep -q "custom-gotify" "$CONFIG"; then
      echo "Appending Gotify integration to $CONFIG"
      # Insert before the last </ossec_config>
      sed -i "s|.*</ossec_config>.*|<integration>\n    <name>custom-gotify</name>\n    <api_key>${GOTIFY_TOKEN}</api_key>\n    <alert_format>json</alert_format>\n  </integration>\n</ossec_config>|" "$CONFIG"
    else
      echo "Gotify integration already configured in $CONFIG. Updating token."
      python3 -c "
import re
with open('$CONFIG', 'r') as f:
    content = f.read()
# Update api_key value
pattern = r'(<integration>\s*<name>custom-gotify</name>\s*<api_key>)(.*?)(</api_key>)'
replacement = r'\g<1>${GOTIFY_TOKEN}\g<3>'
content = re.sub(pattern, replacement, content, flags=re.DOTALL)
with open('$CONFIG', 'w') as f:
    f.write(content)
"
    fi
  fi


  # Enable UDP Syslog listener (port 514) for OPNsense remote log forwarding
  if ! grep -q "<port>514</port>" "$CONFIG"; then
    echo "Enabling remote syslog listener on port 514 UDP for OPNsense"
    sed -i "s|.*</ossec_config>.*|<remote>\n    <connection>syslog</connection>\n    <port>514</port>\n    <protocol>udp</protocol>\n    <allowed-ips>192.168.11.1/32</allowed-ips>\n  </remote>\n</ossec_config>|" "$CONFIG"
  fi

  # Copy CA certs to Wazuh chroot so python inside integratord can verify SSL
  echo "==> Copying CA certificates to Wazuh chroot environment"
  mkdir -p /var/ossec/etc/ssl/certs
  cp -Lf /etc/ssl/certs/ca-certificates.crt /var/ossec/etc/ssl/certs/ca-certificates.crt || true
  chown -R root:wazuh /var/ossec/etc/ssl
  chmod -R 750 /var/ossec/etc/ssl
  chmod 640 /var/ossec/etc/ssl/certs/ca-certificates.crt

  # ── Internal Network Scanner (Local Nmap Port Sweeper) ──────────────────────
  echo "==> Setting up local Nmap port sweeper scanner and alerts"
  apt-get install -y nmap

  # Generate the sweeper python script
  cat > /var/ossec/bin/nmap-sweep.py << 'EOF'
#!/var/ossec/framework/python/bin/python3
import subprocess
import json
import os

baseline = {
    "192.168.11.50": [9090, 9100],
    "192.168.11.51": [3000, 9100],
    "192.168.11.52": [9221, 9100],
    "192.168.11.53": [80, 443, 9100],
    "192.168.11.54": [9100],
    "192.168.11.55": [6667, 6697, 9100],
    "192.168.11.56": [9093, 9100],
    "192.168.11.57": [1514, 1515, 514, 55000],
    "192.168.11.70": [3000, 9100],
    "192.168.11.71": [3001, 9100],
}

log_path = "/var/log/nmap-sweep.log"

try:
    result = subprocess.run(
        ["nmap", "-sT", "-F", "--open", "192.168.11.0/24", "-oX", "-"],
        capture_output=True, text=True, check=True
    )
    import xml.etree.ElementTree as ET
    root = ET.fromstring(result.stdout)
    alert_count = 0
    for host in root.findall('host'):
        ip = host.find("address").get("addr")
        ports_found = []
        ports_node = host.find("ports")
        if ports_node is not None:
            for port_node in ports_node.findall("port"):
                port_id = int(port_node.get("portid"))
                state = port_node.find("state").get("state")
                if state == "open":
                    ports_found.append(port_id)
        expected = baseline.get(ip, [])
        for p in ports_found:
            if p not in expected:
                alert_count += 1
                log_entry = {
                    "integration": "nmap-sweep",
                    "alert": "unexpected_open_port",
                    "ip": ip,
                    "port": p,
                    "status": "unexpected"
                }
                with open(log_path, "a") as lf:
                    lf.write(json.dumps(log_entry) + "\n")
    summary = {
        "integration": "nmap-sweep",
        "alert": "scan_completed",
        "status": "clean" if alert_count == 0 else "dirty",
        "unexpected_count": alert_count
    }
    with open(log_path, "a") as lf:
        lf.write(json.dumps(summary) + "\n")
except Exception as e:
    with open(log_path, "a") as lf:
        lf.write(json.dumps({"integration": "nmap-sweep", "alert": "scan_failed", "error": str(e)}) + "\n")
EOF
  chmod 750 /var/ossec/bin/nmap-sweep.py

  # Set up cron job for daily scan
  echo "0 1 * * * root /var/ossec/bin/nmap-sweep.py" > /etc/cron.d/nmap-sweep

  # Configure local log monitoring in ossec.conf
  if ! grep -q "/var/log/nmap-sweep.log" "$CONFIG"; then
    sed -i "s|.*</ossec_config>.*|<localfile>\n    <log_format>json</log_format>\n    <location>/var/log/nmap-sweep.log</location>\n  </localfile>\n</ossec_config>|" "$CONFIG"
  fi

  # Add custom decoder/rules to local_rules.xml
  RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
  echo "Writing clean custom ruleset to $RULES_FILE"
  cat > "$RULES_FILE" << 'EOF'
<group name="local,syslog,sshd,">

  <!-- Default SSH Rule Example -->
  <rule id="100001" level="5">
    <if_sid>5716</if_sid>
    <srcip>1.1.1.1</srcip>
    <description>sshd: authentication failed from IP 1.1.1.1.</description>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,</group>
  </rule>

  <!-- MacBookPro rootcheck suppression -->
  <rule id="100022" level="0">
    <if_sid>510</if_sid>
    <hostname>MacBookPro</hostname>
    <description>Ignore host-based anomaly detection (rootcheck) on MacBookPro.</description>
  </rule>

  <!-- Silence generic LXC container rootcheck anomalies -->
  <rule id="100023" level="0">
    <if_sid>510</if_sid>
    <match>present on /dev. Possible hidden file.|Trojaned version of file '/bin/diff'|Trojaned version of file '/usr/bin/diff'|is owned by root and has written permissions to anyone</match>
    <description>Silence generic LXC rootcheck false positives (hidden LXC dev files, diff signature matches, and terraform temp scripts).</description>
  </rule>

  <!-- Nmap sweep detection -->
  <rule id="100100" level="3">
    <decoded_as>json</decoded_as>
    <field name="integration">nmap-sweep</field>
    <description>Subnet port sweep completed</description>
  </rule>
  <rule id="100101" level="8">
    <if_sid>100100</if_sid>
    <field name="alert">unexpected_open_port</field>
    <description>Security Warning: Unexpected open port $(port) detected on $(ip)</description>
  </rule>

  <!-- Trivy container vulnerability scanner rules -->
  <rule id="100200" level="3">
    <decoded_as>json</decoded_as>
    <field name="integration">trivy-docker</field>
    <description>Trivy Docker vulnerability scan log</description>
  </rule>
  <rule id="100201" level="7">
    <if_sid>100200</if_sid>
    <field name="severity">HIGH</field>
    <description>Trivy: High vulnerability $(vulnerability) found in Docker image $(image) (package: $(package))</description>
  </rule>
  <rule id="100202" level="9">
    <if_sid>100200</if_sid>
    <field name="severity">CRITICAL</field>
    <description>Trivy: Critical vulnerability $(vulnerability) found in Docker image $(image) (package: $(package))</description>
  </rule>

  <!-- Silence AppArmor mount denials in unprivileged LXC containers -->
  <rule id="100300" level="0">
    <if_sid>52002</if_sid>
    <match>apparmor="DENIED" operation="mount"</match>
    <description>Silence AppArmor mount denials inside unprivileged LXC containers.</description>
  </rule>

  <!-- Silence port status changes globally -->
  <rule id="100024" level="0">
    <if_sid>533</if_sid>
    <description>Ignore local development port changes globally.</description>
  </rule>

  <!-- Silence wazuh-modulesd segfault warnings (known vulnerability scanner bug) -->
  <rule id="100025" level="0">
    <if_sid>1010</if_sid>
    <match>wazuh-modulesd</match>
    <description>Ignore segfault warnings for wazuh-modulesd daemon.</description>
  </rule>

</group>
EOF
  chown root:wazuh "$RULES_FILE"
  chmod 660 "$RULES_FILE"
fi

# ── 3. Enable & Start Services ────────────────────────────────────────────────
echo "==> Ensuring services are enabled and started"
systemctl daemon-reload || true
systemctl enable wazuh-manager wazuh-indexer wazuh-dashboard || true
systemctl restart wazuh-manager || true
systemctl start wazuh-indexer || true
systemctl start wazuh-dashboard || true

echo "==> Wazuh setup and configuration finished!"
if [ -f /root/wazuh-passwords.txt ]; then
  echo "Credentials are saved in /root/wazuh-passwords.txt"
fi
