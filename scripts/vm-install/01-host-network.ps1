<#
  Laptop side of the lab network. Run once in an elevated PowerShell, after creating
  VMnet2/3/4 in VMware's Virtual Network Editor (see README, step 1):
    Set-ExecutionPolicy -Scope Process Bypass
    .\01-host-network.ps1
  Gives the VMnet4 host adapter 10.0.3.10 (VMware defaults it to .1, which pfSense needs)
  and routes 10.0.0.0/16 through pfSense so lab traffic is filtered and logged.
#>
param(
  [string]$Adapter = 'VMware Network Adapter VMnet4',
  [string]$HostIp = '10.0.3.10',
  [string]$LabGateway = '10.0.3.1'
)
$ErrorActionPreference = 'Stop'
$nic = Get-NetAdapter -Name $Adapter -ErrorAction SilentlyContinue
if (-not $nic) { throw "Adapter '$Adapter' not found. Create VMnet4 with 'Connect a host virtual adapter' ticked." }

Get-NetIPAddress -InterfaceAlias $Adapter -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object IPAddress -ne $HostIp | Remove-NetIPAddress -Confirm:$false
if (-not (Get-NetIPAddress -InterfaceAlias $Adapter -IPAddress $HostIp -ErrorAction SilentlyContinue)) {
  New-NetIPAddress -InterfaceAlias $Adapter -IPAddress $HostIp -PrefixLength 24 | Out-Null
}
# No default gateway on this adapter: only lab traffic goes to pfSense, internet stays on Wi-Fi.
if (-not (Get-NetRoute -DestinationPrefix '10.0.0.0/16' -ErrorAction SilentlyContinue)) {
  route -p add 10.0.0.0 mask 255.255.0.0 $LabGateway | Out-Null
}
Get-NetIPAddress -InterfaceAlias $Adapter -AddressFamily IPv4 | Format-Table IPAddress, PrefixLength
Write-Host "Done. After pfSense is installed, open https://$LabGateway from this laptop."
