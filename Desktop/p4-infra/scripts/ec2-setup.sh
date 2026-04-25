#!/usr/bin/env bash
# EC2 Bootstrap Script — SecureChat
# Runs automatically on first boot via Terraform user_data.
# Safe to re-run manually: sudo bash ec2-setup.sh
set -euo pipefail

LOG="/var/log/securechat-setup.log"
exec > >(tee -a "$LOG") 2>&1

echo "======================================================"
echo " SecureChat EC2 Setup — $(date)"
echo "======================================================"

# ── 1. OS Updates ─────────────────────────────────────────────────────────────
echo "[1/9] Updating OS packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# ── 2. Node.js 20 LTS ─────────────────────────────────────────────────────────
echo "[2/9] Installing Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
node --version
npm --version

# ── 3. NGINX ──────────────────────────────────────────────────────────────────
echo "[3/9] Installing NGINX..."
apt-get install -y nginx
systemctl enable nginx

# ── 4. PM2 ────────────────────────────────────────────────────────────────────
echo "[4/9] Installing PM2..."
npm install -g pm2
pm2 startup systemd -u ubuntu --hp /home/ubuntu

# ── 5. Certbot (Let's Encrypt) ────────────────────────────────────────────────
echo "[5/9] Installing Certbot..."
apt-get install -y snapd
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

# ── 6. AWS CloudWatch Agent ───────────────────────────────────────────────────
echo "[6/9] Installing CloudWatch Agent..."
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

# ── 7. MySQL Client (for running migrations) ──────────────────────────────────
echo "[7/9] Installing MySQL client..."
apt-get install -y mysql-client

# ── 8. App directory + log directories ───────────────────────────────────────
echo "[8/9] Creating app directory structure..."
mkdir -p /opt/securechat
mkdir -p /var/log/securechat
mkdir -p /var/www/certbot

chown -R ubuntu:ubuntu /opt/securechat
chown -R ubuntu:ubuntu /var/log/securechat

# NGINX config
cp /opt/securechat/nginx/securechat.conf /etc/nginx/sites-available/securechat
ln -sf /etc/nginx/sites-available/securechat /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# CloudWatch agent config
cp /opt/securechat/cloudwatch/amazon-cloudwatch-agent.json \
   /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
   -a fetch-config -m ec2 -s \
   -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# ── 9. Load secrets from SSM and start app ────────────────────────────────────
echo "[9/9] Loading secrets from SSM and starting application..."
/opt/securechat/scripts/load-env.sh

cd /opt/securechat
sudo -u ubuntu pm2 start ecosystem.config.js
sudo -u ubuntu pm2 save

echo "======================================================"
echo " Setup complete. SecureChat is running."
echo "======================================================"
