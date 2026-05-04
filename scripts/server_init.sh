#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y ca-certificates curl gnupg wget python3-boto3 awscli

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

mkdir -p /opt/hashtopolis
cd /opt/hashtopolis

wget https://raw.githubusercontent.com/hashtopolis/server/dev/docker-compose.mysql.yml -O docker-compose.yml
wget https://raw.githubusercontent.com/hashtopolis/server/dev/env.mysql.example -O .env

sed -i 's/HASHTOPOLIS_APIV2_ENABLE=0/HASHTOPOLIS_APIV2_ENABLE=1/' .env

docker compose up --detach

until docker exec hashtopolis-db mysqladmin ping -uroot -p"\$MYSQL_ROOT_PASSWORD" --silent; do
  sleep 2
done

until docker exec hashtopolis-backend test -d /var/www/html/src/static; do
  sleep 2
done

# Wait for the API to actually accept auth (a few seconds after the static dir appears)
until curl -sf -o /dev/null -X POST -u admin:hashtopolis http://127.0.0.1:8080/api/v2/auth/token; do
  sleep 2
done

TOKEN=$(curl -sS -X POST -u admin:hashtopolis http://127.0.0.1:8080/api/v2/auth/token \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# Look up voucherDeletion config row by name (id varies across versions)
CFG_ID=$(curl -sS -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:8080/api/v2/ui/configs?maxResults=500" \
  | python3 -c "import sys,json; print(next(r['_id'] for r in json.load(sys.stdin)['values'] if r.get('item')=='voucherDeletion'))")

# Enable multi-use vouchers (UI: Config -> Server -> "Vouchers can be used multiple times...")
curl -sS -X PATCH -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"value":"1"}' "http://127.0.0.1:8080/api/v2/ui/configs/$CFG_ID" >/dev/null

# Create a fresh voucher and push it to Secrets Manager so agents can register
VOUCHER=$(python3 -c 'import secrets; print(secrets.token_hex(4))')
curl -sS -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d "{\"voucher\":\"$VOUCHER\"}" http://127.0.0.1:8080/api/v2/ui/vouchers >/dev/null

aws secretsmanager put-secret-value \
  --region ${region} \
  --secret-id ${voucher_secret_id} \
  --secret-string "$VOUCHER" >/dev/null

# Rotate the admin password from the default to the random value TF seeded into SM.
# Hashtopolis intentionally blocks self-rotation through the public API, so we
# write the password directly to MySQL using Hashtopolis's own bcrypt+pepper
# hashing routine (invoked inside the backend container so the pepper config
# loads correctly).
DESIRED_PW=$(aws secretsmanager get-secret-value \
  --region ${region} --secret-id ${password_secret_id} \
  --query SecretString --output text)

NEW_SALT=$(python3 -c 'import secrets,string; print("".join(secrets.choice(string.ascii_letters+string.digits) for _ in range(20)))')
NEW_HASH=$(docker exec hashtopolis-backend php -r 'require_once "/var/www/html/src/inc/load.php"; echo Encryption::passwordHash($argv[1], $argv[2]);' -- "$DESIRED_PW" "$NEW_SALT")

echo "UPDATE User SET passwordHash='$NEW_HASH', passwordSalt='$NEW_SALT', isComputedPassword=0 WHERE userId=1;" \
  | docker exec -i hashtopolis-db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" hashtopolis'

# Verify by attempting to auth with the new password. If it fails for any
# reason, rewrite SM with the default so the scaler still authenticates.
if curl -sf -o /dev/null -X POST -u "admin:$DESIRED_PW" http://127.0.0.1:8080/api/v2/auth/token; then
  echo "[bootstrap] admin password rotated successfully"
else
  echo "[bootstrap] admin password rotation FAILED, falling back to default"
  aws secretsmanager put-secret-value \
    --region ${region} --secret-id ${password_secret_id} \
    --secret-string "hashtopolis" >/dev/null
fi

cat >/etc/hashtopolis-scaler.env <<ENV
HASHTOPOLIS_URL=http://127.0.0.1:8080
ASG_NAME=${asg_name}
MAX_INSTANCES=${max_instances}
HASHTOPOLIS_USERNAME=${hashtopolis_username}
HASHTOPOLIS_PASSWORD_SECRET_ID=${password_secret_id}
REGION=${region}
ENV

cat >/usr/local/bin/hashtopolis-scaler <<'SCALER'
${scaler_py}
SCALER
chmod +x /usr/local/bin/hashtopolis-scaler

cat >/etc/systemd/system/hashtopolis-scaler.service <<'SERVICE'
[Unit]
Description=Hashtopolis ASG scaler
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/hashtopolis-scaler.env
ExecStart=/usr/local/bin/hashtopolis-scaler
SERVICE

cat >/etc/systemd/system/hashtopolis-scaler.timer <<'TIMER'
[Unit]
Description=Run hashtopolis-scaler every minute

[Timer]
OnBootSec=30sec
OnUnitActiveSec=3sec
AccuracySec=1sec
Unit=hashtopolis-scaler.service

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl enable --now hashtopolis-scaler.timer
