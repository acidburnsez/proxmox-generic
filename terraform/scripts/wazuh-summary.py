#!/var/ossec/framework/python/bin/python3
import sys
import json
from datetime import datetime, timedelta, timezone
import urllib.request
import ssl
from collections import Counter

# Configuration
ALERTS_FILE = "/var/ossec/logs/alerts/alerts.json"
WEBHOOK_URL = sys.argv[1] if len(sys.argv) > 1 else ""

if not WEBHOOK_URL:
    sys.stderr.write("Error: Webhook URL is required.\n")
    sys.exit(1)

# Time window: last 24 hours
now = datetime.now(timezone.utc)
time_threshold = now - timedelta(hours=24)

# Aggregation variables
total_alerts = 0
level_distribution = Counter()
agent_alerts = Counter()
rule_alerts = Counter()
auth_failures = []
firewall_blocks = Counter()
suricata_alerts = Counter()
high_severity_alerts = []

# Parse alerts.json
try:
    with open(ALERTS_FILE, 'r') as f:
        for line in f:
            try:
                alert = json.loads(line)
                # Parse timestamp: e.g. "2026-07-06T00:36:32.464+0000"
                ts_str = alert.get("timestamp", "")
                if not ts_str:
                    continue
                # Normalize timezone format
                ts_str_clean = ts_str.replace("+0000", "+00:00")
                alert_time = datetime.fromisoformat(ts_str_clean)
                
                if alert_time < time_threshold:
                    continue
                
                total_alerts += 1
                rule = alert.get("rule", {})
                level = rule.get("level", 0)
                level_distribution[level] += 1
                
                agent_name = alert.get("agent", {}).get("name", "Wazuh Server")
                agent_alerts[agent_name] += 1
                
                description = rule.get("description", "No description")
                rule_alerts[description] += 1
                
                # Check for high severity
                if level >= 10:
                    high_severity_alerts.append({
                        "agent": agent_name,
                        "description": description,
                        "level": level,
                        "time": alert_time.strftime("%H:%M:%S")
                    })
                
                # Categorize alerts
                groups = rule.get("groups", [])
                
                # Authentication failures
                if "authentication_failed" in groups or "invalid_login" in groups:
                    srcip = alert.get("data", {}).get("srcip", "unknown")
                    srcuser = alert.get("data", {}).get("srcuser", "unknown")
                    auth_failures.append(f"{srcuser}@{srcip} on {agent_name}")
                
                # Firewall blocks
                if "firewall" in groups or "pve-firewall" in groups or "opnsense" in groups or "sshd" not in groups and "blocked" in description.lower():
                    srcip = alert.get("data", {}).get("srcip", alert.get("data", {}).get("src_ip", "unknown"))
                    firewall_blocks[srcip] += 1
                    
                # Suricata / Nginx attacks
                if "ids" in groups or "suricata" in groups:
                    suricata_alerts[description] += 1
                    
            except Exception as e:
                continue
except FileNotFoundError:
    sys.stderr.write(f"Alerts file not found at {ALERTS_FILE}\n")
    sys.exit(1)

if total_alerts == 0:
    print("No alerts found in the last 24 hours.")
    sys.exit(0)

# Build summary strings
auth_fail_summary = ""
if auth_failures:
    auth_counts = Counter(auth_failures)
    auth_fail_summary = "\n".join([f"• {count}x failed login: `{user}`" for user, count in auth_counts.most_common(5)])
else:
    auth_fail_summary = "• No failed logins recorded."

fw_summary = ""
if firewall_blocks:
    fw_summary = "\n".join([f"• {count}x packets blocked from `{ip}`" for ip, count in firewall_blocks.most_common(5)])
else:
    fw_summary = "• No firewall blocks recorded."

high_sev_summary = ""
if high_severity_alerts:
    high_sev_summary = "\n".join([f"• [{item['time']}] Level {item['level']} - {item['agent']}: *{item['description']}*" for item in high_severity_alerts[:5]])
else:
    high_sev_summary = "• None."

# Determine color based on max severity
max_level = max(level_distribution.keys()) if level_distribution else 0
if max_level >= 12:
    color = 15158332  # Red
elif max_level >= 8:
    color = 15102720  # Orange/Yellow
else:
    color = 3066993   # Green

# ── Ollama Local AI Security Analyst ──────────────────────────────────────────
ai_analysis = "• Analysis currently unavailable (could not reach Ollama)."
try:
    # Build text representation of alerts for LLM context
    summary_txt = f"Total Alerts: {total_alerts}\n"
    summary_txt += f"Max Severity: Level {max_level}\n\n"
    
    summary_txt += "Authentication Failures:\n"
    if auth_failures:
        for f in auth_failures[:10]:
            summary_txt += f" - {f}\n"
    else:
        summary_txt += " - None\n"
        
    summary_txt += "\nFirewall Blocks:\n"
    if firewall_blocks:
        for ip, count in firewall_blocks.most_common(5):
            summary_txt += f" - {ip}: {count} blocks\n"
    else:
        summary_txt += " - None\n"
        
    summary_txt += "\nHigh Severity Alerts:\n"
    if high_severity_alerts:
        for item in high_severity_alerts[:5]:
            summary_txt += f" - [{item['time']}] Level {item['level']} - {item['agent']}: {item['description']}\n"
    else:
        summary_txt += " - None\n"

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
        "model": "llama3:8b",
        "prompt": (
            "You are a senior security engineer monitoring a personal production environment. "
            "Use the provided Environment Architecture Map to contextualize the logs.\n\n"
            f"{system_context}"
            "Analyze these security logs from the last 24 hours. Provide a brief analysis of potential "
            "threats (max 2-3 sentences) and exactly 3 concrete, actionable remediation steps. "
            "Keep the output extremely concise and formatted as markdown bullet points.\n\n"
            f"Logs:\n{summary_txt}"
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
    
    # HTTP request does not need SSL verification context
    with urllib.request.urlopen(req_ollama, timeout=60) as resp_ollama:
        ollama_data = json.loads(resp_ollama.read().decode('utf-8'))
        ai_analysis = ollama_data.get("response", "No analysis returned from model.")
except Exception as e:
    ai_analysis = f"⚠️ *Ollama AI analysis could not be generated: {e}*"

# Build Discord Embed payload
payload = {
    "embeds": [{
        "title": "📊 Wazuh Personal Production Security Summary (Last 24 Hours)",
        "color": color,
        "description": f"Total Alerts Processed: **{total_alerts}**\nMax Severity Level: **Level {max_level}**",
        "fields": [
            {
                "name": "🔒 Authentication Failures",
                "value": auth_fail_summary,
                "inline": False
            },
            {
                "name": "🛡️ Firewall Blocks",
                "value": fw_summary,
                "inline": False
            },
            {
                "name": "🚨 High-Severity Alerts (Level >= 10)",
                "value": high_sev_summary,
                "inline": False
            },
            {
                "name": "🤖 AI Security Analyst Recommendation (llama3:8b)",
                "value": ai_analysis,
                "inline": False
            },
            {
                "name": "🖥️ Alert Counts by Agent",
                "value": "\n".join([f"• **{agent}**: {count} alerts" for agent, count in agent_alerts.most_common(5)]),
                "inline": True
            },
            {
                "name": "📋 Top Alert Rules Fired",
                "value": "\n".join([f"• {count}x: {rule[:40]}..." for rule, count in rule_alerts.most_common(5)]),
                "inline": True
            }
        ],
        "footer": {
            "text": "Wazuh SIEM Daily Report"
        },
        "timestamp": now.isoformat()
    }]
}

# Send to Discord
req = urllib.request.Request(
    WEBHOOK_URL,
    data=json.dumps(payload).encode('utf-8'),
    headers={
        'Content-Type': 'application/json',
        'User-Agent': 'Wazuh-Reporter'
    }
)

try:
    # Use standard CA certificate verification from host trust store
    context = ssl.create_default_context()
    with urllib.request.urlopen(req, context=context) as response:
        print("Summary report successfully sent to Discord!")
        sys.exit(0)
except Exception as e:
    sys.stderr.write(f"Error sending summary to Discord: {e}\n")
    sys.exit(1)
