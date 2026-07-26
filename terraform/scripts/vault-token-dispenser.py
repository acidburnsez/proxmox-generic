#!/usr/bin/env python3
import socket
import json
import urllib.request
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler

LISTEN_PORT = 8000
TAILSCALE_SOCKET = '/var/run/tailscale/tailscaled.sock'
VAULT_URL = 'http://127.0.0.1:8200/v1/auth/token/create'
TOKEN_FILE = '/etc/vault-token-dispenser.token'
ALLOWED_USER = 'sv2hc8hvtk@privaterelay.appleid.com'

def query_tailscale_whois(client_ip):
    """Query the local tailscaled daemon using Unix socket to get peer identity."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(TAILSCALE_SOCKET)
        # Format HTTP request to localapi whois endpoint (use HTTP/1.0 & Connection: close to avoid hangs)
        req = f"GET /localapi/v0/whois?addr={client_ip} HTTP/1.0\r\nConnection: close\r\n\r\n"
        sock.sendall(req.encode('utf-8'))
        
        # Read response until connection closes
        response = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            response += chunk
            
        parts = response.split(b"\r\n\r\n", 1)
        if len(parts) < 2:
            return None
        body = parts[1].decode('utf-8')
        return json.loads(body)
    except Exception as e:
        print(f"Error querying tailscaled: {e}")
        return None
    finally:
        sock.close()

def create_vault_token():
    """Request a short-lived token from Vault using the stored parent/dispenser token."""
    try:
        with open(TOKEN_FILE, 'r') as f:
            token = f.read().strip()
            
        payload = {
            "ttl": "5m",
            "policies": ["proxmox-read", "default", "k8s-read"],
            "meta": {
                "authenticated_by": "tailscale-whois"
            }
        }
        
        req = urllib.request.Request(
            VAULT_URL,
            data=json.dumps(payload).encode('utf-8'),
            headers={
                'X-Vault-Token': token,
                'Content-Type': 'application/json'
            }
        )
        
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            return data['auth']['client_token']
    except FileNotFoundError:
        print("Vault dispenser token file not found. Vault must be initialized/unsealed first.")
        return "vault-uninitialized"
    except Exception as e:
        print(f"Error generating token from Vault: {e}")
        return None

class TokenDispenserHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Override to prevent log spam in journald
        pass

    def do_GET(self):
        # Parse query parameters
        parsed_path = urllib.parse.urlparse(self.path)
        
        if parsed_path.path != '/token':
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not Found")
            return

        # 1. Identify client source IP address
        client_ip = self.client_address[0]
        
        # 2. Check if IP is in Tailscale subnet (100.64.0.0/10)
        # Note: If client is localhost (e.g. testing), allow it
        is_tailscale = False
        if client_ip.startswith('100.'):
            is_tailscale = True
        elif client_ip in ('127.0.0.1', '::1'):
            is_tailscale = True

        if not is_tailscale:
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b"Forbidden: Request must originate from Tailscale network.")
            return

        # 3. Query Tailscale Whois to verify identity
        if client_ip in ('127.0.0.1', '::1'):
            user_login = ALLOWED_USER
        else:
            whois_data = query_tailscale_whois(client_ip)
            if not whois_data or 'UserProfile' not in whois_data:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Forbidden: Unable to verify Tailscale node identity.")
                return
            user_login = whois_data['UserProfile'].get('LoginName', '')

        # 4. Enforce user authorization check
        if user_login != ALLOWED_USER:
            self.send_response(403)
            self.end_headers()
            self.wfile.write(f"Forbidden: User '{user_login}' is not authorized to retrieve tokens.".encode('utf-8'))
            return

        # 5. Generate and return the Vault token
        vault_token = create_vault_token()
        if not vault_token:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"Internal Server Error: Failed to generate Vault token.")
        elif vault_token == "vault-uninitialized":
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b"Service Unavailable: Vault is sealed or token dispenser not initialized.")
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(vault_token.encode('utf-8'))

def run_server():
    server = HTTPServer(('0.0.0.0', LISTEN_PORT), TokenDispenserHandler)
    print(f"Tailscale-to-Vault Token Dispenser running on port {LISTEN_PORT}...")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

if __name__ == '__main__':
    run_server()
