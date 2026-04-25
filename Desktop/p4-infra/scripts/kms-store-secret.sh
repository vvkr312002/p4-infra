#!/usr/bin/env bash
# kms-store-secret.sh — Store a secret in SSM Parameter Store, encrypted via KMS.
# Usage: ./kms-store-secret.sh <PARAM_NAME> <SECRET_VALUE>
#
# Run once for each of these after terraform apply:
#   ./kms-store-secret.sh DB_HOST    "<rds_address from terraform output>"
#   ./kms-store-secret.sh DB_NAME    "securechat"
#   ./kms-store-secret.sh DB_USER    "admin"
#   ./kms-store-secret.sh DB_PASS    "<your db password>"
#   ./kms-store-secret.sh JWT_SECRET "$(openssl rand -base64 64)"
#   ./kms-store-secret.sh KMS_KEY_ID "<kms_key_id from terraform output>"

set -euo pipefail

REGION="us-east-1"
PROJECT="securechat"
KMS_ALIAS="alias/securechat-secrets"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <PARAM_NAME> <SECRET_VALUE>"
  exit 1
fi

PARAM_NAME="$1"
SECRET_VALUE="$2"
FULL_PATH="/$PROJECT/$PARAM_NAME"

echo "Storing /$PROJECT/$PARAM_NAME in SSM (encrypted with KMS key: $KMS_ALIAS)..."

aws ssm put-parameter \
  --name "$FULL_PATH" \
  --type "SecureString" \
  --key-id "$KMS_ALIAS" \
  --value "$SECRET_VALUE" \
  --overwrite \
  --region "$REGION"

echo "Done. Secret stored at $FULL_PATH — no plaintext retained."
echo ""
echo "Verify with:"
echo "  aws ssm get-parameter --name $FULL_PATH --with-decryption --region $REGION --query Parameter.Value --output text"
