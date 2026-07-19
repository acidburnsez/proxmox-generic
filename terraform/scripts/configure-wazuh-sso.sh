#!/usr/bin/env bash
set -euo pipefail

INDEXER_CONFIG="/etc/wazuh-indexer/opensearch-security/config.yml"
ROLES_MAPPING="/etc/wazuh-indexer/opensearch-security/roles_mapping.yml"
DASHBOARD_CONFIG="/etc/wazuh-dashboard/opensearch_dashboards.yml"

# 1. Update config.yml to insert openid_auth_domain
echo "==> Configuring openid_auth_domain in Indexer config.yml"
# Copy system CA certificates to indexer directory so Java Security Manager allows reading it
cp -f /etc/ssl/certs/ca-certificates.crt /etc/wazuh-indexer/opensearch-security/ca-certificates.crt
chown wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/opensearch-security/ca-certificates.crt
chmod 644 /etc/wazuh-indexer/opensearch-security/ca-certificates.crt

python3 -c "
import re
with open('$INDEXER_CONFIG', 'r') as f:
    content = f.read()

# Remove any existing openid_auth_domain block to ensure clean re-runs
content = re.sub(r'\s+openid_auth_domain:.*?\n\s+authentication_backend:\n\s+type: noop\n', '', content, flags=re.DOTALL)

auth_domain = '''      openid_auth_domain:
        description: \"Authenticate via OpenID Connect (Authelia SSO)\"
        http_enabled: true
        transport_enabled: true
        order: 1
        http_authenticator:
          type: openid
          challenge: false
          config:
            subject_key: sub
            roles_key: groups
            openid_connect_url: https://auth.example.com/.well-known/openid-configuration
            openid_connect_idp:
              enable_ssl: true
              verify_hostnames: true
              pemtrustedcas_filepath: /etc/wazuh-indexer/opensearch-security/ca-certificates.crt
        authentication_backend:
          type: noop
'''

content = content.replace('    authc:', '    authc:\n' + auth_domain)

with open('$INDEXER_CONFIG', 'w') as f:
    f.write(content)
"

# 2. Update roles_mapping.yml to map Authelia admins group
if ! grep -q "admins" "$ROLES_MAPPING"; then
  echo "==> Mapping 'admins' group to 'all_access' in roles_mapping.yml"
  python3 -c "
with open('$ROLES_MAPPING', 'r') as f:
    content = f.read()

content = content.replace('  backend_roles:\n  - \"admin\"', '  backend_roles:\n  - \"admin\"\n  - \"admins\"')

with open('$ROLES_MAPPING', 'w') as f:
    f.write(content)
"
fi

# 3. Apply security changes to the indexer database using securityadmin.sh
echo "==> Applying indexer security configuration"
export JAVA_HOME=/usr/share/wazuh-indexer/jdk
/usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
  -cacert /etc/wazuh-indexer/certs/root-ca.pem \
  -cert /etc/wazuh-indexer/certs/admin.pem \
  -key /etc/wazuh-indexer/certs/admin-key.pem \
  -h 127.0.0.1 -cd /etc/wazuh-indexer/opensearch-security/

# 4. Update opensearch_dashboards.yml
echo "==> Configuring opensearch_dashboards.yml"
python3 -c "
with open('$DASHBOARD_CONFIG', 'r') as f:
    content = f.read()

import re
content = re.sub(r'#\s*opensearch.username:\s*kibanaserver', 'opensearch.username: \"kibanaserver\"', content)
content = re.sub(r'#\s*opensearch.password:\s*kibanaserver', 'opensearch.password: \"YOUR_KIBANASERVER_PASSWORD\"', content)

if 'opensearch_security.auth.type' not in content:
    oidc_settings = '''
opensearch.requestHeadersAllowlist: [\"securitytenant\",\"Authorization\",\"x-forwarded-for\"]
opensearch_security.auth.multiple_auth_enabled: true
opensearch_security.auth.type: [\"basicauth\", \"openid\"]
opensearch_security.openid.connect_url: \"https://auth.example.com/.well-known/openid-configuration\"
opensearch_security.openid.base_redirect_url: \"https://wazuh.example.com\"
opensearch_security.openid.client_id: \"wazuh\"
opensearch_security.openid.client_secret: \"WazuhOidcSecret2026\"
'''
    content += oidc_settings

content = content.replace('opensearch.requestHeadersAllowlist: [\"securitytenant\",\"Authorization\"]', '')

with open('$DASHBOARD_CONFIG', 'w') as f:
    f.write(content)
"

# 5. Restart services
echo "==> Restarting indexer and dashboard services"
systemctl restart wazuh-indexer
systemctl restart wazuh-dashboard
