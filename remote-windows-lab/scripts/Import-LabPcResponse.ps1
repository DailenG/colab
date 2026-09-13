[CmdletBinding()]
param([string]$TransferRoot, [string]$SshAlias)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RemoteLab.Common.ps1')
$root = Resolve-RemoteLabTransferRoot -TransferRoot $TransferRoot
$responses = @(Get-ChildItem -LiteralPath (Join-Path $root 'OMP-Remote-Lab') -Filter lab-response.json -Recurse -File -ErrorAction SilentlyContinue)
if ($responses.Count -eq 0) { throw "No lab-response.json was found on '$root'. Complete lab-PC initialization and return the USB drive." }
if ($responses.Count -gt 1) { throw 'Multiple lab responses were found. Remove/archive stale bundles or provide a USB containing one active transfer.' }
$response = Read-RemoteLabJson -Path $responses[0].FullName
if ($response.schema_version -ne '1.0') { throw 'Unsupported response schema.' }
$device = $response.lab_device
if ($SshAlias) { $device.ssh_alias = $SshAlias }
$device.state = 'bootstrap_applied'
$device.updated_at_utc = [DateTimeOffset]::UtcNow.ToString('O')
Update-RemoteLabRegistryDevice -Device $device | Out-Null
Write-Host "Imported lab device $($device.hostname). Test SSH key login, then tell OMP: mark $($device.hostname) SSH verified."
