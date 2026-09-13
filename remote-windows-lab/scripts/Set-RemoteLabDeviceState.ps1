[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Hostname,
    [Parameter(Mandatory)][ValidateSet('discovered','transfer_prepared','bootstrap_applied','ssh_verified','omp_pending','ready','retired','error')][string]$State,
    [string]$Note
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RemoteLab.Common.ps1')
$path = Get-RemoteLabRegistryPath
$registry = Read-RemoteLabJson -Path $path
if (-not $registry) { throw "No registry exists at '$path'." }
$device = @($registry.devices | Where-Object hostname -EQ $Hostname)
if ($device.Count -ne 1) { throw "Expected one registered lab device named '$Hostname'; found $($device.Count)." }
$device[0].state = $State
$device[0].updated_at_utc = [DateTimeOffset]::UtcNow.ToString('O')
if ($Note) { $device[0].notes = @($device[0].notes) + $Note }
Update-RemoteLabRegistryDevice -Device $device[0] | Out-Null
Write-Host "$Hostname is now recorded as $State."
