#!/usr/bin/env bash
# One-command bring-up of the Wazuh stack on wazuh01. Idempotent.
set -euo pipefail
cd "$(dirname "$0")/../wazuh"
[[ -f .env ]] || { echo "Copy .env.example to .env and fill it in first."; exit 1; }
set -a; . ./.env; set +a
: "${ENROLL_PASSWORD:?}"
# Indexer needs this kernel setting.
[[ $(sysctl -n vm.max_map_count) -ge 262144 ]] || sudo sysctl -w vm.max_map_count=262144
mkdir -p secrets
umask 077; printf '%s\n' "$ENROLL_PASSWORD" > secrets/authd.pass
[[ -f config/certs/root-ca.pem ]] || docker compose -f generate-indexer-certs.yml run --rm generator
../scripts/render-users.sh
docker compose up -d
echo "Dashboard: https://10.0.1.10  (user admin, password from .env)"
