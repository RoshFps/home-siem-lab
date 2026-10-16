#!/bin/sh
set -eu
CONF=/var/ossec/etc/ossec.conf
sed -i "s|<address>.*</address>|<address>${WAZUH_MANAGER}</address>|" "$CONF"
if ! grep -q '/var/log/nginx/access.log' "$CONF"; then
  sed -i '/<\/ossec_config>/d' "$CONF"
  cat /localfile.conf >> "$CONF"
fi
if [ ! -s /var/ossec/etc/client.keys ]; then
  /var/ossec/bin/agent-auth -m "$WAZUH_MANAGER" -P "$WAZUH_REGISTRATION_PASSWORD" -A "$WAZUH_AGENT_NAME"
fi
/var/ossec/bin/wazuh-control start
# Keep the container in the foreground and follow the agent log.
exec tail -F /var/ossec/logs/ossec.log
