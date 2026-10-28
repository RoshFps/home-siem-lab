# Lesson 1: Build the lab network (Jira SIEM 1.2, SCRUM-40)

Goal: three isolated virtual networks on your laptop, plus the laptop joined to one of them. About 30 minutes.
Why it matters for the job: network segmentation is the first thing a client's security review checks, and the thing most breaches exploit when it is missing.

## The ideas first

**IP address and subnet.** An IP address like 10.0.1.10 names a machine. The `/24` in 10.0.1.0/24 means the first three numbers (10.0.1) identify the network and the last number (0-255) identifies the machine, so one /24 holds up to 254 machines. Two machines in the same /24 talk directly. To reach another /24 they must go through a router (here, the pfSense firewall).

**Private ranges.** 10.0.0.0/8, 172.16.0.0/12 and 192.168.0.0/16 are reserved for internal use and are never routed on the internet. Labs and company networks use them. That is why we use 10.0.x.x.

**Segmentation.** Splitting one flat network into zones and putting a firewall between them. If an attacker takes over web01, a flat network lets them reach everything; a segmented one lets them reach only what the firewall allows, and every attempt is logged. This is called limiting lateral movement. In an interview, say those two words.

**DMZ.** The zone for machines that face untrusted users (web servers). The rule of thumb: the DMZ may send logs in to the security zone on a few ports, but the security zone and the internal network never trust the DMZ.

**Host-only network (VMware).** A virtual switch that connects VMs and, optionally, your laptop, with no outside access. We use it so all traffic has to cross pfSense, which is what makes it filterable and loggable.

## The three networks

| VMware name | Purpose | Subnet | Gateway (pfSense) | Host adapter |
| --- | --- | --- | --- | --- |
| VMnet2 | Security (wazuh01 lives here) | 10.0.1.0/24 | 10.0.1.1 | Off |
| VMnet3 | DMZ (web01 lives here) | 10.0.2.0/24 | 10.0.2.1 | Off |
| VMnet4 | Endpoints (your laptop as a workstation) | 10.0.3.0/24 | 10.0.3.1 | On |

## Steps, with the reason for each

1. Open VMware Workstation > **Edit > Virtual Network Editor**, click **Change Settings** (needs admin rights to modify virtual switches).
2. Click **Add Network**, choose VMnet2. Set type to **Host-only**.
   * **Untick "Use local DHCP service"**: DHCP hands out addresses automatically. We assign fixed addresses so logs and firewall rules always refer to the same machine, and so VMware's DHCP does not compete with pfSense.
   * **Untick "Connect a host virtual adapter"**: your laptop gets no direct path into this network. Anything you do must go through the firewall, like a real admin workstation would.
   * Set **Subnet IP** 10.0.1.0 and **Mask** 255.255.255.0.
3. Repeat for VMnet3 (10.0.2.0, no host adapter, no DHCP).
4. Repeat for VMnet4 (10.0.3.0, no DHCP) but **tick "Connect a host virtual adapter"**. The laptop acts as the Windows workstation, so it needs a foot in this network.
5. Leave VMnet8 (NAT) alone. It is the "internet" side of pfSense.
6. Apply, then in an admin PowerShell from the repo folder run:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\scripts\vm-install\01-host-network.ps1
   ```
   What it does: VMware gives the laptop's VMnet4 adapter 10.0.3.1, which pfSense needs for itself, so the script moves the laptop to 10.0.3.10. It then adds a route `10.0.0.0/16 via 10.0.3.1`, meaning "to reach any lab network, ask the firewall". `Set-ExecutionPolicy -Scope Process` relaxes PowerShell's script block for this window only, which is safer than changing it machine-wide.

## Check your work (do not skip: verifying is the professional habit)

```powershell
Get-NetIPAddress -InterfaceAlias "VMware Network Adapter VMnet4" -AddressFamily IPv4   # expect 10.0.3.10
route print | findstr 10.0.0.0                                                          # expect a 10.0.0.0 255.255.0.0 route via 10.0.3.1
```
It will not ping 10.0.3.1 yet, because pfSense does not exist until the next lesson. That is expected.

## Common mistakes
* Ticking DHCP on a network: addresses change and pfSense rules break.
* Forgetting the host adapter on VMnet4 only, then being unable to reach the pfSense web page later.
* Running the script before the VMnet4 adapter exists: it stops with an "adapter not found" message.

## Interview and client talking points
* "I segmented the lab into security, DMZ and endpoint zones behind a firewall with default-deny and logging, so I can show how lateral movement is blocked and detected."
* Know the difference between a switch (same network) and a router/firewall (between networks).

## Quiz yourself
1. How many machines fit in a /24? Which addresses are the network and broadcast?
2. Why does the Security network have no host adapter?
3. If web01 is compromised, what can it reach once the pfSense rules from lesson 2 are in place?

Next: Lesson 2, build fw01 (pfSense) and write the firewall rules (SCRUM-41, SCRUM-57, SCRUM-42).
