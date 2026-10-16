#!/usr/bin/env bash
# web01: Nginx web server in the DMZ, with auditd and the Wazuh agent.
# Run on a fresh Ubuntu Server 24.04 VM (1 vCPU, 1.5 GB RAM, 25 GB disk) as root:
#   sudo ENROLL_PASSWORD='<same as wazuh01>' bash 04-web01-setup.sh
set -euo pipefail

IP_ADDR="10.0.2.20/24"
GATEWAY="10.0.2.1"
DNS="10.0.2.1"
HOSTNAME_NEW="web01"
MANAGER="10.0.1.10"
ENROLL_PASSWORD="${ENROLL_PASSWORD:-}"

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }
[[ -n "$ENROLL_PASSWORD" ]] || { echo "Set ENROLL_PASSWORD (same value used on wazuh01)."; exit 1; }

echo "== 1/6 Static IP and hostname"
IFACE=$(ip -o link show | awk -F': ' '$2!="lo"{print $2; exit}')
cat > /etc/netplan/60-lab.yaml <<NET
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses: [${IP_ADDR}]
      routes: [{to: default, via: ${GATEWAY}}]
      nameservers: {addresses: [${DNS}], search: [lab.local]}
NET
chmod 600 /etc/netplan/60-lab.yaml
rm -f /etc/netplan/50-cloud-init.yaml
netplan apply
hostnamectl set-hostname "$HOSTNAME_NEW"
timedatectl set-timezone UTC

echo "== 2/6 Updates, Nginx, auditd"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx auditd audispd-plugins curl gnupg unattended-upgrades ufw
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl enable --now nginx auditd

echo "== 3/6 Audit rules (process execution, identity and sudo changes, web root)"
cat > /etc/audit/rules.d/60-lab.rules <<'RULES'
-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=unset -k exec_user
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=unset -k exec_root
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /var/www/ -p wa -k webroot
-w /etc/nginx/ -p wa -k nginx_config
RULES
augenrules --load

echo "== 4/6 Wazuh agent"
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
apt-get update -y
WAZUH_MANAGER="$MANAGER" WAZUH_REGISTRATION_PASSWORD="$ENROLL_PASSWORD" WAZUH_AGENT_NAME="$HOSTNAME_NEW" \
  DEBIAN_FRONTEND=noninteractive apt-get install -y wazuh-agent
# Hold the agent version so an apt upgrade never puts it ahead of the manager.
apt-mark hold wazuh-agent

echo "== 5/6 Extra log sources for the agent"
CONF=/var/ossec/etc/ossec.conf
if ! grep -q '/var/log/nginx/access.log' "$CONF"; then
  python3 - "$CONF" <<'PY'
import sys
path = sys.argv[1]
block = """  <localfile>
    <log_format>apache</log_format>
    <location>/var/log/nginx/access.log</location>
  </localfile>
  <localfile>
    <log_format>apache</log_format>
    <location>/var/log/nginx/error.log</location>
  </localfile>
  <localfile>
    <log_format>audit</log_format>
    <location>/var/log/audit/audit.log</location>
  </localfile>
  <syscheck>
    <directories realtime="yes" check_all="yes">/var/www,/etc/nginx</directories>
  </syscheck>
</ossec_config>"""
text = open(path).read()
text = text.replace("</ossec_config>", block, 1)
open(path, "w").write(text)
PY
fi
systemctl daemon-reload
systemctl enable --now wazuh-agent
systemctl restart wazuh-agent

echo "== 6/6 Host firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow from 10.0.3.0/24 to any port 22 proto tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo
echo "Done. In the Wazuh dashboard, Agents should list web01 as Active within a minute."
