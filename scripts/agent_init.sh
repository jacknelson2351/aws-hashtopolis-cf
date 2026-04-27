#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y software-properties-common
add-apt-repository universe -y
apt-get update -y
apt-get install -y ca-certificates curl hashcat pocl-opencl-icd p7zip-full python3 python3-requests python3-psutil
