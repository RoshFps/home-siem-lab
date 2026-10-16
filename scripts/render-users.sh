#!/usr/bin/env bash
# Renders wazuh/config/wazuh_indexer/internal_users.yml from the template using the passwords in wazuh/.env.
set -euo pipefail
cd "$(dirname "$0")/../wazuh"
set -a; . ./.env; set +a
: "${INDEXER_PASSWORD:?}" "${DASHBOARD_PASSWORD:?}" "${WAZUH_VERSION:?}"
hash() {
  docker run --rm -i "wazuh/wazuh-indexer:${WAZUH_VERSION}" bash -c \
    'JAVA_HOME=/usr/share/wazuh-indexer/jdk /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p "$0" 2>/dev/null | tail -n1' "$1"
}
admin=$(hash "$INDEXER_PASSWORD"); kib=$(hash "$DASHBOARD_PASSWORD")
sed -e "s|__ADMIN_HASH__|${admin}|" -e "s|__KIBANA_HASH__|${kib}|" \
  config/wazuh_indexer/internal_users.yml.tpl > config/wazuh_indexer/internal_users.yml
echo "Wrote config/wazuh_indexer/internal_users.yml"
