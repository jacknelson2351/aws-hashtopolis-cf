#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y ca-certificates curl gnupg wget

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

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
