# Advanced setup guide: what each setting does, when to use it, how to harden it

`docs/RUNBOOK.md` is the quick path. This guide explains the settings behind it and the custom options for more control, security and customization. Each item says what it does, when it helps, and the trade-off.

## 1. Network and segmentation (pfSense, VMnet2/3/4)

| Setting | What it does | When to use it |
| --- | --- | --- |
| Three host-only networks (Security 10.0.1.0/24, DMZ 10.0.2.0/24, Endpoints 10.0.3.0/24) | Every packet between zones crosses pfSense, so it is filtered and logged | Always. This is the point of the lab: a compromised web01 cannot reach wazuh01 except on ports you allow |
| No host adapter on VMnet2/3 | Your laptop has no direct path into Security or DMZ | Keeps the laptop from bypassing the firewall. VMnet4 has one because the laptop is the endpoint |
| "Log" on every pfSense rule | Each allow or block becomes a syslog line to Wazuh | Always on; it is the data your detections use |
| Default deny | Anything not listed is blocked | Add rules only when a service breaks, and only for the exact port and host |

Custom options: add a fourth segment (for example 10.0.4.0/24 "Attacker", a Kali VM) that can reach DMZ and Endpoints but never Security. This gives realistic attack tests (Jira SIEM 4.x) without risking the SIEM. Trade-off: one more VM, so check the RAM budget in `docs/SCALING.md`.

## 2. wazuh/.env

| Variable | What it does | Guidance |
| --- | --- | --- |
| `WAZUH_VERSION` | Image tag for manager, indexer and dashboard | Pin it. Upgrade deliberately: back up volumes, change the tag, `docker compose pull && docker compose up -d`. Agents must not be newer than the manager |
| `INDEXER_HEAP` | JVM heap of the indexer (`-Xms`/`-Xmx`) | Rule of thumb: half the container limit, never above 31 GB. 2g suits the 3 GB limit. Raise it only if you also raise `mem_limit` |
| `INDEXER_PASSWORD` | Password of the `admin` user (dashboard login and the manager's Filebeat) | Random, 8-64 chars with upper, lower, digit and symbol. The bootstrap script generates one |
| `DASHBOARD_PASSWORD` | `kibanaserver`, used only by the dashboard to talk to the indexer | Different from admin; nobody logs in with it |
| `API_PASSWORD` | `wazuh-wui`, the Wazuh API account the dashboard uses | Different again. API is bound to 127.0.0.1:55000 on purpose |
| `ENROLL_PASSWORD` | Password an agent must present to register | Stops a rogue VM on the network from enrolling itself. Rotate it by editing `.env`, re-running `scripts/up-wazuh.sh`; already-enrolled agents keep working |

Hardening beyond the defaults:
* Create a read-only analyst user in the dashboard (Security > Internal users, role `readall`) and use it for daily work; keep `admin` for changes.
* Keep `wazuh/.env` at mode 600 and back it up in your password manager, never in the repo (`.gitignore` already blocks it).
* Put the dashboard behind your own certificate: replace `wazuh.dashboard.pem` and its key in `wazuh/config/certs/`. Use it when other people will open the dashboard and you want no browser warning.

## 3. docker-compose settings (wazuh/)

* `mem_limit` per container: a runaway container is killed instead of starving the VM. Keep the sum below the VM RAM minus about 1 GB for the OS.
* `ulimits memlock` and `nofile`: the indexer locks its heap in RAM (no swapping, steady latency) and needs many open files. Do not lower them.
* `vm.max_map_count=262144`: kernel setting the indexer requires; `up-wazuh.sh` sets it for the current boot. Make it permanent with `echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-wazuh.conf`.
* Published ports: 1514/tcp (agent events, encrypted), 1515/tcp (enrollment), 514/udp (pfSense syslog), 443 (dashboard). The indexer port 9200 is deliberately not published. Do not publish it: it holds all your logs.
* `restart: unless-stopped`: the stack comes back after a reboot of wazuh01.

## 4. Manager settings (wazuh_manager.conf)

| Block | What it does | Tune it when |
| --- | --- | --- |
| `<remote><connection>secure` (1514) | Encrypted, authenticated agent channel | Never change |
| `<remote><connection>syslog` with `<allowed-ips>10.0.1.1</allowed-ips>` | Accepts plain syslog only from pfSense | If pfSense's source IP changes, update it. Never use 0.0.0.0/0 |
| `<auth><use_password>yes` | Requires the enrollment password | Keep on |
| `<logall>no` / `<logall_json>yes` | Controls raw-event archives | Set `logall` to yes when you need every event for threat hunting or to write new rules (costs disk; the 365-day archive policy covers it) |
| `<alerts><log_alert_level>3` | Minimum rule level stored as an alert | Raise to 5+ if the indexer fills too fast; lower to see more |
| `<syscheck>` (file integrity) | Hashes watched directories and alerts on change | Add `<directories check_all="yes" realtime="yes">/var/www</directories>` on web hosts to catch web shells instantly. Realtime costs CPU, so use it only on small, critical paths |
| `<vulnerability-detection>` | Matches installed packages to CVE feeds | Keep on; needs internet from wazuh01 for the feeds |
| `<sca>` | Scores a host against CIS-style benchmarks | Run it before and after hardening web01 to show the improvement in your portfolio |
| `<active-response>` | Lets the manager run a block or script on an agent when a rule fires | Powerful and risky: start in detect-only mode, then enable `firewall-drop` for a single rule (for example repeated SSH failures) with a short timeout so you cannot lock yourself out |

## 5. Retention and storage

30 days searchable (indexer), 365 days gzipped archives. To change it, adjust the index lifecycle policy in the dashboard (Index Management > State management policies) and the archive cleanup cron. Longer hot retention needs more disk: estimate GB per day from `docker system df` and the Indexer > Indices page, then multiply. Take a snapshot or at least back up the named volumes before upgrades.

## 6. Agents

* Linux (web01): the container agent only sees Nginx logs. For auditd, syscalls and FIM on the host itself, install the agent on the VM (`scripts/vm-install/04-web01-setup.sh`). Choose containers for easy rebuilds, the VM agent for deeper host visibility.
* Windows (laptop): Sysmon with the SwiftOnSecurity config records process creation, network connections and file hashes. Use a stricter or noisier config (for example Olaf Hartong's modular) when you want more detection coverage and accept more events.
* Agent groups: put agents in groups (web, windows) and give each group its own `agent.conf` from the dashboard, so you tune collection per role without touching each host.

## 7. Security checklist before you call it done

1. Change the pfSense admin password; disable WAN access to the web UI.
2. Confirm 9200 and 55000 are unreachable from other VMs (`nc -zv 10.0.1.10 9200` from web01 must fail).
3. `.env`, certificates and `internal_users.yml` are not in git (CI enforces secrets and keys).
4. Snapshots of every VM after a clean install, so you can reset after attack tests.
5. Create the analyst user and stop using `admin` for daily work.

When you want any of these customizations applied to the repo (compose changes, extra segment, Sysmon variant, active response), tell me which and I will implement and explain it step by step.
