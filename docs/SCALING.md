# Scaling the lab

## RAM budget on a 16 GB laptop

| Item | RAM |
| --- | --- |
| Windows host + VMware | ~5 GB |
| wazuh01 VM (manager 1.5 GB, indexer 3 GB with 2 GB heap, dashboard 1 GB) | 6 GB |
| fw01 (pfSense) | 1 GB |
| web01 VM (Nginx 128 MB, agent 384 MB, OS) | 1.5 GB |
| Headroom | ~2.5 GB |

Container `mem_limit`s in the compose files enforce this, so one container cannot starve the VM.

## Ways to grow

1. **More log sources, no new VM:** add a service to `web01/docker-compose.yml` (for example a second app) that writes logs to a named volume, and mount the volume read-only into `wazuh-agent` plus a `<localfile>` entry in `web01/agent/localfile.conf`. `docker compose up -d --scale` works for stateless services.
2. **More DMZ hosts:** run the same `web01/` stack on another VM (own IP in 10.0.2.0/24, own `WAZUH_AGENT_NAME`). pfSense rules for the DMZ already allow 1514/1515 to Wazuh.
3. **More disk:** alerts are about 30 days hot (indexer volume `wazuh-indexer-data`), archives 365 days gzipped. Grow the wazuh01 disk first (120 GB today), then move `/var/lib/docker` to a bigger disk. Check with `docker system df`.
4. **More SIEM capacity:** when one laptop is out of RAM, move `wazuh/` to a second machine or cloud VM and point agents at it (`WAZUH_MANAGER`). For multi-node, switch to upstream `wazuh-docker/multi-node`; the agents and pfSense do not change.
5. **Reproducibility:** pin `WAZUH_VERSION` in `.env`, upgrade by changing it and running `docker compose pull && docker compose up -d`. Back up the named volumes and `.env` before upgrades (see the runbook).

## What stays outside Docker

pfSense (BSD firewall, needs its own VM) and the Windows laptop agent. Host-level auditd and file-integrity monitoring on web01 need the agent on the VM itself; the container agent only sees Nginx logs.
