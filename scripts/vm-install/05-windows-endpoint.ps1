<#
  Laptop (Windows host) as the lab's Windows endpoint: Sysmon + Wazuh agent + lab route.
  Run in an elevated PowerShell AFTER the lab network, pfSense and wazuh01 are up:
    Set-ExecutionPolicy -Scope Process Bypass
    .\05-windows-endpoint.ps1 -EnrollPassword '<same as wazuh01>'
#>
param(
  [Parameter(Mandatory = $true)][string]$EnrollPassword,
  [string]$Manager = '10.0.1.10',
  [string]$LabGateway = '10.0.3.1',
  [string]$WazuhVersion = ''   # e.g. 4.12.0; empty = latest release. Must not be newer than wazuh01.
)
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this from an elevated (Administrator) PowerShell.'
}
$work = Join-Path $env:ProgramData 'SocLab'
New-Item -ItemType Directory -Force -Path $work | Out-Null

Write-Host '== 1/4 Route lab traffic through pfSense'
if (-not (Get-NetRoute -DestinationPrefix '10.0.0.0/16' -ErrorAction SilentlyContinue)) {
  route -p add 10.0.0.0 mask 255.255.0.0 $LabGateway | Out-Null
}
if (-not (Test-NetConnection $Manager -Port 1514 -InformationLevel Quiet)) {
  throw "Cannot reach $Manager on 1514/tcp. Check pfSense rules and the VMnet4 adapter (10.0.3.10)."
}

Write-Host '== 2/4 Sysmon with the SwiftOnSecurity config'
Invoke-WebRequest 'https://download.sysinternals.com/files/Sysmon.zip' -OutFile "$work\Sysmon.zip"
Expand-Archive "$work\Sysmon.zip" -DestinationPath "$work\Sysmon" -Force
Invoke-WebRequest 'https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml' -OutFile "$work\sysmonconfig.xml"
if (Get-Service Sysmon64 -ErrorAction SilentlyContinue) {
  & "$work\Sysmon\Sysmon64.exe" -c "$work\sysmonconfig.xml"
} else {
  & "$work\Sysmon\Sysmon64.exe" -accepteula -i "$work\sysmonconfig.xml"
}

Write-Host '== 3/4 Wazuh agent'
if (-not $WazuhVersion) {
  $WazuhVersion = (Invoke-RestMethod 'https://api.github.com/repos/wazuh/wazuh/releases/latest').tag_name.TrimStart('v')
}
$major = $WazuhVersion.Split('.')[0]
$msi = "$work\wazuh-agent-$WazuhVersion-1.msi"
Invoke-WebRequest "https://packages.wazuh.com/$major.x/windows/wazuh-agent-$WazuhVersion-1.msi" -OutFile $msi
Start-Process msiexec.exe -Wait -ArgumentList @('/i', "`"$msi`"", '/q',
  "WAZUH_MANAGER=$Manager", "WAZUH_REGISTRATION_PASSWORD=$EnrollPassword", "WAZUH_AGENT_NAME=$env:COMPUTERNAME")

Write-Host '== 4/4 Event channels: Sysmon, PowerShell, Defender'
$conf = "${env:ProgramFiles(x86)}\ossec-agent\ossec.conf"
$text = Get-Content $conf -Raw
if ($text -notmatch 'Microsoft-Windows-Sysmon/Operational') {
  $extra = @'
  <localfile>
    <location>Microsoft-Windows-Sysmon/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>
  <localfile>
    <location>Microsoft-Windows-PowerShell/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>
  <localfile>
    <location>Microsoft-Windows-Windows Defender/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>
</ossec_config>
'@
  $idx = $text.IndexOf('</ossec_config>')
  $text = $text.Substring(0, $idx) + $extra + $text.Substring($idx + '</ossec_config>'.Length)
  Set-Content -Path $conf -Value $text -Encoding ASCII
}
# PowerShell script block logging feeds the PowerShell/Operational channel.
New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Force |
  Set-ItemProperty -Name EnableScriptBlockLogging -Value 1
Restart-Service WazuhSvc
Write-Host "Done. In the Wazuh dashboard, Agents should list $env:COMPUTERNAME as Active within a minute."
