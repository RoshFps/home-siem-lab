# Runbook: from nothing to a running lab

Do the steps in order. Every step is either "click this" or "paste this". Total time is a few hours, mostly installs.
Network, firewall rules and pfSense logging follow `step 2` of the architecture doc (VMnet2 Security 10.0.1.0/24, VMnet3 DMZ 10.0.2.0/24, VMnet4 Endpoints 10.0.3.0/24).

## 1. Laptop: install VMware and download ISOs
VMware Workstation Pro (free, Broadcom account), Ubuntu Server 24.04 ISO, pfSense CE AMD64 ISO.

## 2. Laptop: networks
VMware > Edit > Virtual Network Editor > Change Settings. Add VMnet2 (host-only, no host adapter, no DHCP, 10.0.1.0/24), VMnet3 (host-only, no host adapter, no DHCP, 10.0.2.0/24), VMnet4 (host-only, **host adapter on**, no DHCP, 10.0.3.0/24).
Then, in an admin PowerShell:
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\vm-install\01-host-network.ps1
```

## 3. fw01 (pfSense VM)
1 vCPU, 1 GB RAM, 16 GB disk, adapters in order NAT, VMnet2, VMnet3, VMnet4. Interfaces, rules, DNS and the remote syslog target (10.0.1.10:514) are in the architecture doc (step 2, section 2).

## 4. wazuh01 (Ubuntu VM, 4 vCPU, 6 GB RAM, 120 GB disk, adapter on VMnet2)
Install Ubuntu Server with static IP 10.0.1.10/24, gateway and DNS 10.0.1.1, OpenSSH on. Then:
```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/RoshFps/home-siem-lab && cd home-siem-lab
scripts/bootstrap-wazuh01.sh
```
It installs Docker, creates `wazuh/.env` with random passwords, runs `scripts/preflight.sh wazuh`, and starts the stack. It prints the dashboard password and the **enrollment password**; save both.
After 3-5 minutes: `scripts/smoke-test.sh`, then open https://10.0.1.10 from the laptop (accept the self-signed certificate).

## 5. web01 (Ubuntu VM, 1 vCPU, 1.5 GB RAM, 16 GB disk, adapter on VMnet3)
Static IP 10.0.2.20/24, gateway and DNS 10.0.2.1. Then:
```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/RoshFps/home-siem-lab && cd home-siem-lab
scripts/bootstrap-web01.sh '<enrollment password from step 4>'
```

## 6. Laptop: Windows endpoint
Admin PowerShell, from the cloned repo (or download `scripts/vm-install/05-windows-endpoint.ps1`):
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\vm-install\05-windows-endpoint.ps1 -EnrollPassword '<enrollment password>'
```

## 7. Verify
On wazuh01 run `scripts/smoke-test.sh`: expect `wazuh.manager`, `web01` and the laptop all `active`. In the dashboard, check Agents, then Discover for pfSense syslog events.

## If something fails
* `scripts/preflight.sh wazuh|web01` prints what is wrong (RAM, ports, IP, connectivity).
* `docker compose logs -f` in `wazuh/` or `web01/`.
* Indexer restarts in a loop: check `vm.max_map_count` (`sysctl vm.max_map_count` must be 262144 or more) and the VM has 6 GB.
* Agent not enrolling: same enrollment password on both sides, and pfSense allows 1514/1515 from the DMZ and Endpoints.

Attack tests and detection tuning (Jira SIEM 4.x) come after all three agents are active.
