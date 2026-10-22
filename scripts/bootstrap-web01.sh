#!/usr/bin/env bash
# One command on web01 (Ubuntu 24.04, IP 10.0.2.20): installs Docker if missing and starts Nginx + agent.
# Usage: scripts/bootstrap-web01.sh '<enrollment password printed on wazuh01>'
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
enroll=${1:?usage: bootstrap-web01.sh <enrollment password>}

if ! command -v docker >/dev/null; then
  echo "Installing Docker Engine"
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
fi
if ! docker info >/dev/null 2>&1; then
  exec sg docker -c "$0 '$enroll'"
fi

cp -n web01/.env.example web01/.env
sed -i "s|^ENROLL_PASSWORD=.*|ENROLL_PASSWORD=$enroll|" web01/.env
chmod 600 web01/.env

scripts/preflight.sh web01
cd web01 && docker compose up -d --build
echo "web01 is up. Generate a few hits: curl -s http://10.0.2.20/ >/dev/null; then check the agent in the dashboard."
