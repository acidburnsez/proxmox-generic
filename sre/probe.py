#!/usr/bin/env python3
import urllib.request
import ssl
import time
import json
import socket
from datetime import datetime

DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1520578254501576905/afwPjVAgPSkhcfy1b_xQHyBzmwATWq2q2pJQZCrjzixju2nOEZm94zftK8BmZkhzLIwo/slack"

TARGETS = [
    # Public HTTPS Endpoints
    {"url": "https://auth.example.com", "type": "public", "expected_codes": [200]},
    {"url": "https://homepage.example.com", "type": "sso_redirect", "expected_codes": [302, 401]},
    {"url": "https://grafana.example.com", "type": "sso_redirect", "expected_codes": [302, 401]},
    # Internal ClusterIP Endpoints
    {"url": "http://kube-prometheus-stack-prometheus.monitoring.svc:9090/-/healthy", "type": "internal", "expected_codes": [200]},
    {"url": "http://kube-prometheus-stack-alertmanager.monitoring.svc:9093/-/healthy", "type": "internal", "expected_codes": [200]}
]

def send_alert(url, error_msg, latency=None):
    payload = {
        "username": "SRE Monarch Prober",
        "attachments": [{
            "color": "#ff0000",
            "title": f"🚨 SLO VIOLATION DETECTED: {url}",
            "text": f"**Error**: `{error_msg}`\n**Latency**: `{f'{latency:.3f}s' if latency else 'N/A'}`\n**Timestamp**: {datetime.utcnow().isoformat()}Z",
            "fallback": f"SRE Alert: {url} is failing."
        }]
    }
    req = urllib.request.Request(
        DISCORD_WEBHOOK,
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    try:
        urllib.request.urlopen(req)
    except Exception as e:
        print(f"Failed to send alert: {e}")

def check_ssl_expiry(hostname):
    context = ssl.create_default_context()
    with socket.create_connection((hostname, 443), timeout=5) as sock:
        with context.wrap_socket(sock, server_hostname=hostname) as ssock:
            cert = ssock.getpeercert()
            expire_date = datetime.strptime(cert['notAfter'], '%b %d %H:%M:%S %Y %Z')
            days_left = (expire_date - datetime.utcnow()).days
            return days_left

for target in TARGETS:
    url = target["url"]
    start_time = time.time()
    try:
        # For SSL checks
        if url.startswith("https:"):
            hostname = url.split("//")[1].split("/")[0]
            days_left = check_ssl_expiry(hostname)
            if days_left < 14:
                send_alert(url, f"SSL Certificate expiring soon! Only {days_left} days remaining.")

        # Request check
        context = ssl._create_unverified_context() # Allow self-signed testing if needed
        req = urllib.request.Request(url, headers={'User-Agent': 'SRE-Prober-1.0'})
        
        # Prevent auto-redirect to capture 302 redirects (SSO check)
        class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
            def http_error_302(self, req, fp, code, msg, headers):
                infoclass = urllib.request.HTTPError
                return infoclass(req.get_full_url(), code, msg, headers, fp)

        opener = urllib.request.build_opener(NoRedirectHandler)
        
        code = None
        try:
            with opener.open(req, timeout=5) as response:
                code = response.getcode()
        except urllib.request.HTTPError as e:
            code = e.code
            
        latency = time.time() - start_time
        
        if code not in target["expected_codes"]:
            send_alert(url, f"HTTP Code Mismatch: Expected one of {target['expected_codes']}, got {code}", latency)
        elif latency > 1.0: # SLO check: 99% of requests < 1.0s
            send_alert(url, f"SLO Latency Violation: Latency exceeded 1.0s threshold", latency)
            
        print(f"✓ {url} - Code: {code}, Latency: {latency:.3f}s")
            
    except Exception as e:
        latency = time.time() - start_time
        send_alert(url, str(e), latency)
        print(f"✗ {url} - Failed: {e}")
