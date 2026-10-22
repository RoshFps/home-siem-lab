#!/usr/bin/env bash
# Checks a VM is ready before bring-up. Usage: scripts/preflight.sh wazuh|web01
set -uo pipefail
role=${1:?usage: preflight.sh wazuh|web01}
fail=0
ok()   { echo "  ok   $*"; }
bad()  { echo "  FAIL $*"; fail=1; }
check() { local msg=$1; shift; if "$@" >/dev/null 2>&1; then ok "$msg"; else bad "$msg"; fi; }

case $role in
  wazuh) ip=10.0.1.10; min_ram_mb=5500; min_disk_gb=40; ports="443 1514 1515 514" ;;
  web01) ip=10.0.2.20; min_ram_mb=1200; min_disk_gb=8;  ports="80" ;;
  *) echo "role must be wazuh or web01"; exit 2 ;;
esac

echo "Preflight for $role"
check "docker installed" command -v docker
check "docker compose plugin" docker compose version
check "docker daemon reachable" docker info
check "this VM has $ip" bash -c "ip -4 addr | grep -q 'inet $ip/'"
ram=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
[[ $ram -ge $min_ram_mb ]] && ok "RAM ${ram} MB" || bad "RAM ${ram} MB, need ${min_ram_mb}+"
disk=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
[[ $disk -ge $min_disk_gb ]] && ok "free disk ${disk} GB" || bad "free disk ${disk} GB, need ${min_disk_gb}+"
for p in $ports; do
  check "port $p free" bash -c "! ss -lntu | awk '{print \$5}' | grep -qE '[:.]$p\$'"
done
if [[ $role == wazuh ]]; then
  check "can pull images (hub.docker.com)" curl -fsS -m 10 -o /dev/null https://registry-1.docker.io/v2/
  check "wazuh/.env exists" test -f "$(dirname "$0")/../wazuh/.env"
else
  check "can reach manager 10.0.1.10:1514" bash -c 'timeout 5 bash -c "</dev/tcp/10.0.1.10/1514"'
  check "can reach manager 10.0.1.10:1515" bash -c 'timeout 5 bash -c "</dev/tcp/10.0.1.10/1515"'
  check "can pull ubuntu/wazuh packages" curl -fsS -m 10 -o /dev/null https://packages.wazuh.com/key/GPG-KEY-WAZUH
fi
[[ $fail -eq 0 ]] && echo "Preflight passed." || { echo "Preflight failed: fix the FAIL lines above."; exit 1; }
