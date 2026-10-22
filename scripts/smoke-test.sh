#!/usr/bin/env bash
# Run on wazuh01 after bring-up: containers, dashboard, API and enrolled agents.
set -uo pipefail
cd "$(dirname "$0")/../wazuh" || exit 1
set -a; . ./.env; set +a
docker compose ps
echo "--- dashboard"
curl -ksS -o /dev/null -w "HTTPS 443 -> %{http_code} (200/302 means up)\n" https://127.0.0.1/
echo "--- agents (needs the manager API, up after ~2 min)"
tok=$(curl -ksS -u "wazuh-wui:${API_PASSWORD}" -X POST "https://127.0.0.1:55000/security/user/authenticate?raw=true") || exit 1
curl -ksS -H "Authorization: Bearer $tok" "https://127.0.0.1:55000/agents?select=name,ip,status&limit=20" |
  python3 -c "
import sys, json
for a in json.load(sys.stdin)['data']['affected_items']:
    print(a['name'].ljust(12), a.get('ip', '').ljust(15), a['status'])
"
echo "Expect: wazuh.manager active, web01 active, and the laptop (hostname) active once step 7 is done."
