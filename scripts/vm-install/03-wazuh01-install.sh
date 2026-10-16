#!/usr/bin/env bash
# wazuh01: Wazuh all-in-one (manager + indexer + dashboard) for the home SOC lab.
# Run on a fresh Ubuntu Server 24.04 VM (4 vCPU, 6 GB RAM, 120 GB disk) as root:
#   sudo bash 03-wazuh01-install.sh
# Before running, set ENROLL_PASSWORD below (or export it) to a long random string.
# Keep that password: the agent scripts (04, 05) need the same value.
set -euo pipefail

IP_ADDR="10.0.1.10/24"
GATEWAY="10.0.1.1"
DNS="10.0.1.1"
HOSTNAME_NEW="wazuh01"
PFSENSE_IP="10.0.1.1"          # source IP of pfSense syslog (its Security interface)
INDEXER_HEAP="2g"              # keep at 2g on a 6 GB VM
HOT_DAYS=30                    # alerts kept searchable in the indexer
ARCHIVE_DAYS=365               # gzipped raw archives kept on disk
WAZUH_MAJOR="4.x"
ENROLL_PASSWORD="${ENROLL_PASSWORD:-}"

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }
[[ -n "$ENROLL_PASSWORD" ]] || { echo "Set ENROLL_PASSWORD first: sudo ENROLL_PASSWORD='...' bash $0"; exit 1; }

echo "== 1/8 Static IP and hostname"
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

echo "== 2/8 OS updates and automatic security patches"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get install -y curl tar unattended-upgrades ufw python3
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "== 3/8 Wazuh all-in-one install (takes a while)"
cd /root
curl -sO "https://packages.wazuh.com/${WAZUH_MAJOR}/wazuh-install.sh"
bash ./wazuh-install.sh -a -i   # -i: skip the 8 GB RAM check; we run on 6 GB on purpose
ADMIN_PW=$(tar -O -xf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt \
  | grep -A1 "indexer_username: 'admin'" | grep indexer_password | cut -d"'" -f2)

echo "== 4/8 Cap indexer memory at ${INDEXER_HEAP}"
sed -i -E "s/^-Xms[0-9]+[gGmM]/-Xms${INDEXER_HEAP}/; s/^-Xmx[0-9]+[gGmM]/-Xmx${INDEXER_HEAP}/" /etc/wazuh-indexer/jvm.options
grep -q 'network.host: "127.0.0.1"' /etc/wazuh-indexer/opensearch.yml \
  || echo "WARNING: indexer is not bound to 127.0.0.1; check /etc/wazuh-indexer/opensearch.yml"

echo "== 5/8 Manager: pfSense syslog, raw archives, enrollment password"
OSSEC=/var/ossec/etc/ossec.conf
cp "$OSSEC" "$OSSEC.bak.$(date +%F)"
sed -i 's|<logall_json>no</logall_json>|<logall_json>yes</logall_json>|' "$OSSEC"
sed -i 's|<use_password>no</use_password>|<use_password>yes</use_password>|' "$OSSEC"
if ! grep -q "<allowed-ips>${PFSENSE_IP}</allowed-ips>" "$OSSEC"; then
  python3 - "$OSSEC" "$PFSENSE_IP" <<'PY'
import sys
path, ip = sys.argv[1], sys.argv[2]
block = f"""  <remote>
    <connection>syslog</connection>
    <port>514</port>
    <protocol>udp</protocol>
    <allowed-ips>{ip}</allowed-ips>
    <local_ip>10.0.1.10</local_ip>
  </remote>
</ossec_config>"""
text = open(path).read()
text = text.replace("</ossec_config>", block, 1)
open(path, "w").write(text)
PY
fi
printf '%s\n' "$ENROLL_PASSWORD" > /var/ossec/etc/authd.pass
chown root:wazuh /var/ossec/etc/authd.pass
chmod 640 /var/ossec/etc/authd.pass

echo "== 6/8 Restart services"
systemctl restart wazuh-indexer
systemctl restart wazuh-manager
systemctl restart wazuh-dashboard
sleep 30

echo "== 7/8 Retention: ${HOT_DAYS}-day hot alerts, ${ARCHIVE_DAYS}-day archives"
curl -sk -u "admin:${ADMIN_PW}" -X PUT "https://127.0.0.1:9200/_plugins/_ism/policies/wazuh-alerts-${HOT_DAYS}d" \
  -H 'Content-Type: application/json' -d @- <<JSON
{"policy":{"description":"Delete wazuh alert indices after ${HOT_DAYS} days","default_state":"hot",
 "states":[{"name":"hot","actions":[],"transitions":[{"state_name":"delete","conditions":{"min_index_age":"${HOT_DAYS}d"}}]},
           {"name":"delete","actions":[{"delete":{}}],"transitions":[]}],
 "ism_template":[{"index_patterns":["wazuh-alerts-*"],"priority":100}]}}
JSON
echo
cat > /etc/cron.daily/wazuh-archive-retention <<CRON
#!/bin/sh
find /var/ossec/logs/archives -type f -name '*.gz' -mtime +${ARCHIVE_DAYS} -delete
CRON
chmod 755 /etc/cron.daily/wazuh-archive-retention

echo "== 8/8 Host firewall (pfSense is the main control; this is defence in depth)"
ufw default deny incoming
ufw default allow outgoing
ufw allow from 10.0.3.0/24 to any port 22 proto tcp
ufw allow from 10.0.3.0/24 to any port 443 proto tcp
for net in 10.0.2.0/24 10.0.3.0/24; do
  ufw allow from "$net" to any port 1514 proto tcp
  ufw allow from "$net" to any port 1515 proto tcp
done
ufw allow from "$PFSENSE_IP" to any port 514 proto udp
ufw --force enable

cat <<DONE

Done. Next:
 1. Open https://10.0.1.10 from the laptop and log in as admin.
    All generated passwords: tar -O -xf /root/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt
 2. Change the admin password:  /usr/share/wazuh-indexer/plugins/opensearch-security/tools/wazuh-passwords-tool.sh -u admin -p '<new>'
    Then save every password in a password manager and delete /root/wazuh-install-files.tar.
 3. Run 04-web01-setup.sh on web01 and 05-windows-endpoint.ps1 on the laptop.
DONE
