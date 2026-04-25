#!/usr/bin/env bash
# load-env.sh — Pull KMS-encrypted secrets from SSM Parameter Store
# and export them as environment variables for the current shell / PM2.
#
# Run before starting the app:
#   source /opt/securechat/scripts/load-env.sh
#
# Called automatically by ec2-setup.sh and the GitHub Actions deploy step.

set -euo pipefail

REGION="us-east-1"
PROJECT="securechat"

echo "Loading secrets from SSM (region: $REGION)..."

fetch_param() {
  local name="$1"
  aws ssm get-parameter \
    --name "/$PROJECT/$name" \
    --with-decryption \
    --region "$REGION" \
    --query "Parameter.Value" \
    --output text
}

export DB_HOST=$(fetch_param "DB_HOST")
export DB_NAME=$(fetch_param "DB_NAME")
export DB_USER=$(fetch_param "DB_USER")
export DB_PASS=$(fetch_param "DB_PASS")
export JWT_SECRET=$(fetch_param "JWT_SECRET")
export KMS_KEY_ID=$(fetch_param "KMS_KEY_ID")
export NODE_ENV="production"
export PORT="3000"

# Persist into PM2's managed env so secrets survive app restarts
pm2 set securechat-backend:DB_HOST    "$DB_HOST"    2>/dev/null || true
pm2 set securechat-backend:DB_NAME    "$DB_NAME"    2>/dev/null || true
pm2 set securechat-backend:DB_USER    "$DB_USER"    2>/dev/null || true
pm2 set securechat-backend:DB_PASS    "$DB_PASS"    2>/dev/null || true
pm2 set securechat-backend:JWT_SECRET "$JWT_SECRET" 2>/dev/null || true
pm2 set securechat-backend:KMS_KEY_ID "$KMS_KEY_ID" 2>/dev/null || true

echo "Secrets loaded successfully. No plaintext written to disk."
