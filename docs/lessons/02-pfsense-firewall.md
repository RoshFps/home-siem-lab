# Lesson 2: Build the firewall, fw01 (Jira SIEM 1.3, 1.4, 1.5: SCRUM-41, SCRUM-57, SCRUM-42)

Goal: a pfSense VM that routes between the three zones, blocks everything not allowed, and sends every log to Wazuh. About 1 to 2 hours.
Why it matters for the job: firewall rule design and log review are core daily tasks for SOC analysts and network security engineers. Clients ask "what can reach what, and how would you know if something tried?"

## The ideas first

**Stateful firewall.** It remembers connections. If wazuh01 is allowed to receive an agent connection, the reply traffic is allowed automatically; you only write the rule for the direction that starts the connection.

**Default deny.** Rules are checked top to bottom, first match wins, and anything with no matching rule is dropped. Allow-lists are safer than block-lists because you cannot forget to block something new.

**WAN, LAN, OPT.** pfSense names interfaces by role. WAN faces the internet (here VMware NAT). Every other interface is an internal zone. We rename them so the rules read like English: ENDPOINTS, SECURITY, DMZ.

**NAT.** Internal addresses (10.0.x.x) are private, so on the way out pfSense rewrites the source to its WAN address. This is why lab machines can download updates.

**Aliases.** Named groups of hosts, networks or ports. A rule that says `WAZUH` is readable and survives an IP change; the same rule written with raw IPs is not.

**Syslog.** A standard way for devices to send log lines over the network (UDP 514 here). It is plain text and unauthenticated, which is why the manager only accepts it from 10.0.1.1 (see `allowed-ips` in the manager config).

## Step A: create the VM (SCRUM-41)

1. Create a VM: 1 vCPU, 1 GB RAM, 16 GB disk, guest OS "FreeBSD 14 64-bit". Why so small: pfSense is light, and your 16 GB laptop has to hold five machines.
2. Add four network adapters **in this order**: NAT (VMnet8), VMnet2, VMnet3, VMnet4. Order matters because you will map them to WAN/OPT1/OPT2/LAN by MAC address.
3. Boot the pfSense ISO, accept the license, choose **Install**, then the defaults (ZFS, single disk). Reboot and remove the ISO.
4. At the console menu choose **1) Assign interfaces**. No VLANs. WAN = NAT adapter, LAN = VMnet4 adapter, OPT1 = VMnet2, OPT2 = VMnet3. Compare each MAC with VM Settings > adapter > Advanced.
5. Choose **2) Set interface IP address**: LAN 10.0.3.1/24, OPT1 10.0.1.1/24, OPT2 10.0.2.1/24. Answer **no** to DHCP and no upstream gateway on those three. Why: only WAN has a way out; internal interfaces are the gateways for their networks.
6. From the laptop open https://10.0.3.1 (login admin / pfsense) and run the wizard: hostname `fw01`, domain `lab.local`, **set a strong admin password now**, and untick **Block RFC1918 private networks** on WAN (your NAT network is private, so the default would block your own internet).
7. Interfaces menu: rename LAN to `ENDPOINTS`, OPT1 to `SECURITY`, OPT2 to `DMZ`, tick Enable on each, Save, Apply.

Check: https://10.0.3.1 loads from the laptop, and `ping 10.0.3.1` works.

## Step B: aliases and rules (SCRUM-57)

Firewall > Aliases: `WAZUH` = 10.0.1.10, `WEB` = 10.0.2.20, `LAB_NETS` = 10.0.0.0/16, `PRIVATE_NETS` = 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 (all private ranges, which includes your home network).

Firewall > Rules. Delete the default allow-all rules, keep the anti-lockout rule (it protects your own access to the web UI), and tick **Log packets** on every rule. Add:

| Interface | Protocol | Destination | Ports | Why it exists |
| --- | --- | --- | --- | --- |
| ENDPOINTS | TCP | WAZUH | 1514, 1515, 443, 22 | Agent events, enrollment, dashboard, admin SSH |
| ENDPOINTS | TCP | WEB | 80, 443, 22 | Browse and administer web01 |
| DMZ | TCP | WAZUH | 1514, 1515 | web01 agent only; no dashboard, no SSH into the SIEM |
| DMZ, SECURITY | UDP | This firewall | 53, 123 | DNS and time |
| DMZ, SECURITY | TCP | NOT PRIVATE_NETS | 80, 443 | Package updates from the real internet only. Never into the lab, and never into your home network |

Read the table as the security argument: a compromised web01 can send logs to Wazuh and fetch updates, nothing more. Every blocked attempt is logged.

Check: from web01 later, `nc -zv 10.0.1.10 22` must fail while `nc -zv 10.0.1.10 1514` succeeds.

## Step C: DNS, time and log forwarding (SCRUM-42)

* **DNS Resolver:** enable on all interfaces, add host overrides `wazuh01`, `web01`, `fw01` in `lab.local`, and under Advanced tick **Log Queries**. DNS logs show malware calling home and are a favorite detection source.
* **NTP:** enable on all interfaces. Correct time on every machine is what lets you line up events from different logs during an investigation.
* **Remote logging** (Status > System Logs > Settings): tick *Send log messages to remote syslog server*, source address `SECURITY`, server `10.0.1.10:514`, contents **Everything**, default BSD format.
* Take a backup: Diagnostics > Backup & Restore > Download configuration. Keep it private: it contains secrets. Only a sanitized copy ever goes in the repo (`pfsense/`).

## Keeping the lab away from your home network

VMware's NAT lets a VM reach anything your laptop can reach, which includes your router and the other devices at home. pfSense's WAN sits on that NAT, so the rule above, with destination `NOT PRIVATE_NETS`, is what stops a lab machine from talking to your home devices. If the lab ever contains attack tools or malware tests (SIEM 4.1), this rule is the safety wall. Also:
* Never put a lab VM on a **Bridged** network adapter. Bridged puts it directly on your home network.
* Check your home network's address range (`ipconfig`, look for your Wi-Fi adapter). If it starts with 10.0., the lab's 10.0.x.x addresses clash with it. Tell me and I will move the lab to another range.
* The lab route (`10.0.0.0/16 via 10.0.3.1`) only matters for lab addresses, so it must never overlap your home range.

## Common mistakes
* Adapter order wrong, so WAN lands on the wrong network. Fix by re-assigning by MAC.
* Forgetting the Log tickbox on a rule: no log, no detection.
* Rule on the wrong interface. Rules apply to traffic **entering** the interface they are on.
* Leaving the default admin password.

## Interview and client talking points
* "Default-deny with least-privilege rules per zone, all logged and forwarded to a SIEM, with the config backed up and a sanitized copy versioned in Git."
* Be ready to explain stateful filtering, NAT, and why DMZ-to-security is restricted to log ports.

## Quiz yourself
1. Why are rules evaluated on the entry interface?
2. What breaks if you forget the SECURITY to NOT PRIVATE_NETS rule? What could happen if you wrote it as NOT LAB_NETS instead?
3. Why is syslog over UDP 514 restricted by source IP on the manager?

Next: Lesson 3, wazuh01 (`scripts/bootstrap-wazuh01.sh`) and what each dashboard screen tells you.
