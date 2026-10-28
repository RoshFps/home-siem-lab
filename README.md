# Home SIEM lab (Wazuh, Docker, pfSense)

A Wazuh SIEM lab that runs on one 16 GB laptop under VMware Workstation. pfSense stays a VM; Wazuh and the web server run as Docker Compose stacks, so the whole lab is rebuilt from this repo.

| Machine | Where | IP | Runs |
| --- | --- | --- | --- |
| fw01 | VM, 1 GB RAM | 10.0.1.1 / 10.0.2.1 / 10.0.3.1 | pfSense CE, logs to Wazuh over syslog |
| wazuh01 | VM, 6 GB RAM | 10.0.1.10 (Security) | Docker: `wazuh/` (manager, indexer, dashboard) |
| web01 | VM, 1.5 GB RAM | 10.0.2.20 (DMZ) | Docker: `web01/` (Nginx + Wazuh agent) |
| laptop | host | 10.0.3.10 (Endpoints) | Sysmon + Wazuh agent (`scripts/vm-install/05-windows-endpoint.ps1`) |

The IPs, firewall rules and retention (30 days searchable, 365 days gzipped archives) are the same as the plain-VM install, so both paths produce the same lab.

## Quick start

Full ordered steps are in [docs/RUNBOOK.md](docs/RUNBOOK.md); every setting explained, with hardening and custom options, is in [docs/ADVANCED.md](docs/ADVANCED.md). The short version:

```bash
scripts/bootstrap-wazuh01.sh            # on wazuh01: Docker, random passwords, preflight, stack up
scripts/bootstrap-web01.sh '<enroll pw>' # on web01: Docker, Nginx + agent
scripts/smoke-test.sh                    # on wazuh01: dashboard and agents check
```

Manual equivalent:

```bash
# on wazuh01 (Ubuntu 24.04 with Docker Engine + compose plugin)
cd wazuh && cp .env.example .env     # fill in the passwords
../scripts/up-wazuh.sh               # certs, password hashes, docker compose up -d

# on web01
cd web01 && cp .env.example .env     # same ENROLL_PASSWORD
docker compose up -d --build
```

Then follow the pfSense and laptop steps in `docs/`. `scripts/vm-install/` keeps the original no-Docker scripts as an alternative.

## Layout

* `wazuh/`: single-node Wazuh compose (from wazuh/wazuh-docker v4.14.9, GPLv2), resource limits, syslog input, enrollment password.
* `web01/`: Nginx and an agent sidecar that tails Nginx logs.
* `scripts/`: `bootstrap-*.sh`, `preflight.sh`, `smoke-test.sh`, `up-wazuh.sh`, `render-users.sh`, and `vm-install/` (VM scripts).
* `docs/SCALING.md`: RAM budget and how the lab grows.
* `pfsense/`, `results/`: sanitized pfSense config and attack-test results (added later).
* `.github/workflows/ci.yml`: shellcheck, yamllint, `docker compose config`, agent image build, secret scan.

Nothing secret lives in the repo: `.env`, certificates, rendered user hashes and pfSense XML are git-ignored.

Status: the compose files, scripts (shellcheck) and CI validate; a full run on the lab VMs is still to be done (Jira SIEM 5.2 and 5.3).
