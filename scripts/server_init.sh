#!/bin/bash
set -e

apt-get update -y
apt-get install -y docker.io docker-compose-plugin
systemctl enable --now docker

mkdir -p /opt/hashtopolis
cd /opt/hashtopolis

wget https://raw.githubusercontent.com/hashtopolis/server/dev/docker-compose.mysql.yml -O docker-compose.yml
wget https://raw.githubusercontent.com/hashtopolis/server/dev/env.mysql.example -O .env

sed -i 's/HASHTOPOLIS_APIV2_ENABLE=0/HASHTOPOLIS_APIV2_ENABLE=1/' .env

docker compose up --detach
