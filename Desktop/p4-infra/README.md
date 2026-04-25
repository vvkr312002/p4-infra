# SecureChat — P4 Infrastructure

AWS infrastructure for the SecureChat encrypted messaging application.
Region: **us-east-1** | DB: **MySQL 8.0 on RDS** | Secrets: **KMS + SSM Parameter Store**

---

## Environment Variables

All secrets are stored encrypted in **AWS SSM Parameter Store** under the path `/<param>`.
**No plaintext `.env` files exist on any server.** Secrets are fetched at runtime via `load-env.sh`.

| Variable | SSM Path | Description |
|---|---|---|
| `DB_URL` | `/securechat/DB_URL` | Full MySQL connection string: `mysql://user:pass@host:3306/db` |
| `DB_HOST` | `/securechat/DB_HOST` | RDS endpoint hostname |
| `DB_NAME` | `/securechat/DB_NAME` | Database name (`securechat`) |
| `DB_USER` | `/securechat/DB_USER` | RDS master username |
| `DB_PASS` | `/securechat/DB_PASS` | RDS master password |
| `JWT_SECRET` | `/securechat/JWT_SECRET` | Secret for signing JWTs (≥64 random bytes, base64) |
| `KMS_KEY_ID` | `/securechat/KMS_KEY_ID` | AWS KMS key ID for application-level encryption |
| `NODE_ENV` | — | Set to `production` in ecosystem.config.js |
| `PORT` | — | `3000` (hardcoded in PM2 config, proxied by NGINX) |

### GitHub Actions Secrets (set in repo → Settings → Secrets)

| Secret | Description |
|---|---|
| `EC2_HOST` | Elastic IP of the EC2 application server |
| `EC2_SSH_PRIVATE_KEY` | Private key matching the EC2 key pair |

---

## Architecture

```
Internet
   │  HTTPS (443) / WSS
   ▼
[NGINX on EC2]  ─── /api/* ──────► [Node.js :3000]
                ─── /ws ─────────► [WebSocket :3000]
                ─── /* ──────────► [React build (static)]
                                          │
                              ┌───────────┴───────────┐
                              ▼                       ▼
                       [RDS MySQL]            [SSM Parameter Store]
                    (private subnet,          (KMS-encrypted secrets)
                     not public)
                              │
                        [KMS Key]  ──── encrypts ───► RDS storage
                                   ──── encrypts ───► EBS volume
                                   ──── encrypts ───► CW log group

[GitHub Actions] ── push to main ──► test ──► SSH deploy ──► pm2 restart
[CloudWatch Agent] ─── streams ──► /securechat/app + /securechat/nginx
```

---

## Quick-Start Deployment

### Prerequisites
- AWS CLI configured with admin credentials
- Terraform ≥ 1.6
- An EC2 key pair already created in us-east-1
- A registered domain (optional — configs use `example.com` placeholder)

### Step 1 — Provision infrastructure

```bash
cd terraform/
export TF_VAR_key_pair_name=your-key-pair-name
export TF_VAR_db_password=$(openssl rand -base64 32)
terraform init
terraform plan
terraform apply
```

Save the outputs — you'll need `ec2_public_ip`, `rds_endpoint`, and `kms_key_id`.

### Step 2 — Store secrets in SSM

```bash
# Run from your local machine (AWS CLI must have put-parameter permission)
./scripts/kms-store-secret.sh JWT_SECRET "$(openssl rand -base64 64)"
./scripts/kms-store-secret.sh DB_HOST    "<rds_endpoint from terraform output>"
./scripts/kms-store-secret.sh DB_NAME    "securechat"
./scripts/kms-store-secret.sh DB_USER    "admin"
./scripts/kms-store-secret.sh DB_PASS    "<your TF_VAR_db_password>"
./scripts/kms-store-secret.sh DB_URL     "mysql://admin:<pass>@<rds_endpoint>:3306/securechat"
./scripts/kms-store-secret.sh KMS_KEY_ID "<kms_key_id from terraform output>"
```

### Step 3 — Clone app onto EC2 and run migrations

```bash
ssh ubuntu@<EC2_ELASTIC_IP>
git clone https://github.com/your-org/securechat.git /opt/securechat
cd /opt/securechat

# Run migrations
source scripts/load-env.sh
for f in migrations/*.sql; do
  mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" securechat < "$f"
done

# Start app
pm2 start ecosystem.config.js
pm2 save
```

### Step 4 — TLS certificate

```bash
# On EC2 — replace example.com with your real domain
sudo certbot --nginx -d yourdomain.com
```

### Step 5 — GitHub Actions

Add the following secrets to your GitHub repository:
- `EC2_HOST` → your Elastic IP
- `EC2_SSH_PRIVATE_KEY` → contents of your `.pem` key file

Push to `main` — the CI/CD pipeline handles everything from here.

---

## Sharing the Server URL with the Team

Once TLS is set up, share the following with P1, P2, and P3:

```
SERVER_URL=https://yourdomain.com    (or https://<ELASTIC_IP> before domain)
WS_URL=wss://yourdomain.com/ws
API_BASE=https://yourdomain.com/api
```

**Unblocking order:**
1. P4 shares `SERVER_URL` + runs migrations → everyone can hit the API
2. P2 freezes crypto function signatures → P3 can scaffold integration
3. P1 ships `/register` + `/pubkey` → P3 can complete send flow

---

## Security Checklist

- [ ] No plaintext `.env` files on any server — all secrets via SSM
- [ ] RDS not publicly accessible — only reachable from EC2 SG
- [ ] SSH restricted to admin IP (change `0.0.0.0/0` in `security_groups.tf`)
- [ ] KMS key rotation enabled
- [ ] EBS volume encrypted
- [ ] RDS storage encrypted
- [ ] CloudWatch log group encrypted
- [ ] HTTPS enforced — HTTP redirects to HTTPS
- [ ] Security headers set in NGINX config
- [ ] DB contains only ciphertext in `messages` table (no plaintext)
- [ ] Audit log captures every auth event

---

## Useful Commands

```bash
# View live app logs
pm2 logs securechat-backend

# View CloudWatch logs (AWS CLI)
aws logs tail /securechat/app --follow --region us-east-1

# Check NGINX status
sudo systemctl status nginx

# Reload NGINX without downtime
sudo nginx -t && sudo systemctl reload nginx

# Run a migration manually
mysql -h $DB_HOST -u $DB_USER -p"$DB_PASS" securechat < migrations/001_create_users.sql

# Verify DB has only ciphertext
mysql -h $DB_HOST -u $DB_USER -p"$DB_PASS" securechat \
  -e "SELECT id, from_user_id, LEFT(ciphertext, 60) AS ciphertext_preview FROM messages LIMIT 5;"
```
