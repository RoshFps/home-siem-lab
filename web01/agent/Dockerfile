# Wazuh agent in a container. Version must not be newer than the manager (see WAZUH_VERSION in wazuh/.env).
FROM ubuntu:24.04
ARG WAZUH_VERSION=4.14.9
RUN apt-get update && apt-get install -y --no-install-recommends curl gnupg ca-certificates \
 && curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list \
 && apt-get update && WAZUH_MANAGER=placeholder apt-get install -y --no-install-recommends wazuh-agent=${WAZUH_VERSION}-1 \
 && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
COPY localfile.conf /localfile.conf
RUN chmod 755 /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
