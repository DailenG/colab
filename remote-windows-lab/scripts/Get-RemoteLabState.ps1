[CmdletBinding()]
param([string]$Hostname)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RemoteLab.Common.ps1')
$path = Get-RemoteLabRegistryPath
$registry = Read-RemoteLabJson -Path $path
if (-not $registry) {
    Write-Host "No controller registry exists at $path. Say 'initialize this device as a dev PC' to begin."
    return
}
$rows = @()
if ($registry.controller) { $rows += $registry.controller }
$rows += @($registry.devices)
if ($Hostname) { $rows = @($rows | Where-Object hostname -EQ $Hostname) }
$rows | Select-Object hostname, role, state, @{n='addresses';e={$_.addresses -join ','}}, ssh_alias, updated_at_utc | Format-Table -AutoSize
Write-Host "Registry: $path"
