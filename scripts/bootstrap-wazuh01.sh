#!/usr/bin/env bash
# One command on wazuh01 (Ubuntu 24.04, IP 10.0.1.10): installs Docker if missing,
# creates wazuh/.env with random passwords (first run only), runs preflight and brings the stack up.
# Usage: git clone https://github.com/RoshFps/home-siem-lab && cd home-siem-lab && scripts/bootstrap-wazuh01.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

if ! command -v docker >/dev/null; then
  echo "Installing Docker Engine"
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
fi
# Use sudo for docker if this shell has not picked up the docker group yet.
if ! docker info >/dev/null 2>&1; then
  echo "Re-running under the docker group"
  exec sg docker -c "$0"
fi

rand() { # 20 chars with upper, lower, digit and a symbol, as the Wazuh indexer requires
  local base; base=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 16)
  echo "${base}aZ9.!"
}
if [[ ! -f wazuh/.env ]]; then
  cp wazuh/.env.example wazuh/.env
  for k in INDEXER_PASSWORD DASHBOARD_PASSWORD API_PASSWORD ENROLL_PASSWORD; do
    sed -i "s|^$k=.*|$k=$(rand)|" wazuh/.env
  done
  chmod 600 wazuh/.env
  echo "Created wazuh/.env with random passwords."
fi

scripts/preflight.sh wazuh
scripts/up-wazuh.sh
set -a; . wazuh/.env; set +a
cat <<MSG

Wazuh is starting (the indexer needs 2-5 minutes before the dashboard loads).
  Dashboard : https://10.0.1.10   user admin
  Password  : $INDEXER_PASSWORD
  Enrollment password (for web01 and the laptop): $ENROLL_PASSWORD
Save both in your password manager. They also live in $root/wazuh/.env.
Check progress with: scripts/smoke-test.sh
MSG
