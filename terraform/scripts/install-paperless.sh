#!/usr/bin/env bash
# Installs Paperless-ngx natively inside the LXC container.
# Called by Terraform null_resource — do not run manually.

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DEBIAN_FRONTEND=noninteractive

DOMAIN="${1:-example.com}"

echo "==> Creating paperless system user/group"
groupadd --system paperless || true
useradd --system \
    --gid paperless \
    --create-home \
    --home-dir /opt/paperless \
    --shell /usr/sbin/nologin \
    --comment "Paperless-ngx document manager" \
    paperless || true

echo "==> Installing system dependencies"
apt-get update -qq
apt-get install -y -qq \
    curl tar xz-utils build-essential redis-server pkg-config default-libmysqlclient-dev \
    python3 python3-pip python3-venv python3-dev \
    libpq-dev libjpeg-dev libpng-dev libtiff-dev libwebp-dev libopenjp2-7-dev libgif-dev \
    libxml2-dev libxslt1-dev zlib1g-dev libssl-dev libffi-dev \
    tesseract-ocr tesseract-ocr-eng ghostscript unpaper icc-profiles-free poppler-utils file imagemagick

echo "==> Starting and enabling Redis"
systemctl enable redis-server
systemctl restart redis-server

echo "==> Downloading Paperless-ngx pre-built release"
VERSION="2.14.0"
TARBALL_URL="https://github.com/paperless-ngx/paperless-ngx/releases/download/v${VERSION}/paperless-ngx-v${VERSION}.tar.xz"

curl -sSL -o /tmp/paperless.tar.xz "${TARBALL_URL}"
tar -xf /tmp/paperless.tar.xz -C /opt/paperless --strip-components=1
rm -f /tmp/paperless.tar.xz

echo "==> Preparing directories"
mkdir -p /opt/paperless/data /opt/paperless/media /opt/paperless/consume /opt/paperless/logs
chown -R paperless:paperless /opt/paperless
chmod 750 /opt/paperless/consume

echo "==> Setting up Python virtual environment"
python3 -m venv /opt/paperless/elock
chown -R paperless:paperless /opt/paperless/elock

echo "==> Installing Python dependencies"
# Run pip as the paperless user inside the virtual env
sudo -u paperless /opt/paperless/elock/bin/pip install --upgrade pip
sudo -u paperless /opt/paperless/elock/bin/pip install -r /opt/paperless/requirements.txt

echo "==> Writing paperless.conf"
cat > /opt/paperless/paperless.conf << EOF
# System Configuration
PAPERLESS_REDIS=redis://localhost:6379
PAPERLESS_DBENGINE=sqlite
PAPERLESS_DATA_DIR=/opt/paperless/data
PAPERLESS_MEDIA_ROOT=/opt/paperless/media
PAPERLESS_CONSUMPTION_DIR=/opt/paperless/consume
PAPERLESS_LOGGING_DIR=/opt/paperless/logs

# Web Server Configuration
PAPERLESS_URL=https://paperless.${DOMAIN}
PAPERLESS_PORT=8000
PAPERLESS_BIND_ADDR=0.0.0.0

# OCR Settings
PAPERLESS_OCR_LANGUAGE=eng

# Authelia SSO Integration
PAPERLESS_ENABLE_HTTP_REMOTE_USER=true
PAPERLESS_HTTP_REMOTE_USER_HEADER=HTTP_REMOTE_USER
EOF

chown paperless:paperless /opt/paperless/paperless.conf
chmod 640 /opt/paperless/paperless.conf

echo "==> Running Django database migrations"
sudo -u paperless /opt/paperless/elock/bin/python3 /opt/paperless/src/manage.py migrate

echo "==> Creating default superuser user"
# Create superuser user with password from the standard homelab secrets
sudo -u paperless env DJANGO_SUPERUSER_PASSWORD='YOUR_SECURE_PASSWORD' \
    /opt/paperless/elock/bin/python3 /opt/paperless/src/manage.py createsuperuser \
    --noinput --username=user --email=user@${DOMAIN} || true

echo "==> Writing Systemd Service definitions"

# 1. Webserver Service
cat > /etc/systemd/system/paperless-webserver.service << 'EOF'
[Unit]
Description=Paperless-ngx Web Server
After=network.target redis-server.service

[Service]
Type=simple
User=paperless
Group=paperless
WorkingDirectory=/opt/paperless/src
ExecStart=/opt/paperless/elock/bin/gunicorn -b 0.0.0.0:8000 -w 2 --threads 2 --timeout 90 paperless.wsgi:application
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 2. Worker/Consumer Service
cat > /etc/systemd/system/paperless-consumer.service << 'EOF'
[Unit]
Description=Paperless-ngx Document Consumer
After=network.target redis-server.service paperless-webserver.service

[Service]
Type=simple
User=paperless
Group=paperless
WorkingDirectory=/opt/paperless/src
ExecStart=/opt/paperless/elock/bin/python3 manage.py document_consumer
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 3. Scheduler Service
cat > /etc/systemd/system/paperless-scheduler.service << 'EOF'
[Unit]
Description=Paperless-ngx Celery Scheduler
After=network.target redis-server.service paperless-webserver.service

[Service]
Type=simple
User=paperless
Group=paperless
WorkingDirectory=/opt/paperless/src
ExecStart=/opt/paperless/elock/bin/celery --app paperless beat --loglevel INFO
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Starting Paperless services"
systemctl daemon-reload
systemctl enable paperless-webserver paperless-consumer paperless-scheduler
systemctl restart paperless-webserver paperless-consumer paperless-scheduler

# ── node_exporter ─────────────────────────────────────────────────────────────
echo "==> Installing node_exporter"
apt-get install -y -qq prometheus-node-exporter
systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo "==> Paperless-ngx installation complete!"
