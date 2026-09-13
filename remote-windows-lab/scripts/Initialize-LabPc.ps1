#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param([string]$TransferRoot, [securestring]$InitialPassword)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RemoteLab.Common.ps1')

$root = Resolve-RemoteLabTransferRoot -TransferRoot $TransferRoot
$manifests = @(Get-ChildItem -LiteralPath (Join-Path $root 'OMP-Remote-Lab') -Filter manifest.json -Recurse -File -ErrorAction SilentlyContinue)
if ($manifests.Count -eq 0) { throw "No OMP remote-lab manifest was found on '$root'. Insert the USB prepared by the development PC." }
if ($manifests.Count -gt 1) { throw "Multiple lab bundles were found. Re-run with -TransferRoot pointing to the intended bundle's drive and remove or archive stale bundles." }
$manifestPath = $manifests[0].FullName
$bundle = Split-Path -Parent $manifestPath
$manifest = Read-RemoteLabJson -Path $manifestPath
if ($manifest.schema_version -ne '1.0' -or $manifest.private_key_included -ne $false) { throw 'The transfer manifest is incompatible or claims to include a private key.' }
if (Get-ChildItem -LiteralPath $bundle -Recurse -File | Where-Object { $_.Name -notlike '*.pub' -and $_.Name -match '(^id_(rsa|ed25519)$|\.pem$|private)' }) { throw 'The transfer bundle contains a possible private key and was refused.' }

$publicKey = Get-Content -LiteralPath (Join-Path $bundle $manifest.public_key_file) -Raw
& (Join-Path $PSScriptRoot 'Enable-OmpLabAccess.ps1') -PublicKey $publicKey -AllowedRemoteAddress $manifest.allowed_remote_address -LabUser $manifest.lab_user -InitialPassword $InitialPassword -Confirm:$false

$stateRoot = Join-Path $env:ProgramData 'OmpRemoteLab'
$stagedSkill = Join-Path $stateRoot 'remote-windows-lab'
New-Item -Path $stateRoot -ItemType Directory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $bundle 'skill') -Destination $stagedSkill -Recurse -Force
$device = New-RemoteLabDeviceRecord -Role lab_pc -State omp_pending -TransferId ([guid]$manifest.transfer_id) -SshAlias $manifest.requested_ssh_alias -LabUser $manifest.lab_user -ProjectRepository $manifest.project_repository -Checks @{ ssh_service_running = ((Get-Service sshd).Status -eq 'Running'); firewall_scoped = $true; public_key_installed = $true; omp_user_setup = $false } -Notes @('Sign in interactively as the lab user and run Initialize-OmpLabUser.ps1 from the staged skill.')
Write-RemoteLabJson -Path (Join-Path $stateRoot 'device-state.json') -Value $device
Write-RemoteLabJson -Path (Join-Path $bundle 'lab-response.json') -Value ([ordered]@{ schema_version='1.0'; transfer_id=$manifest.transfer_id; lab_device=$device })

Write-Host 'Lab PC SSH bootstrap completed.'
Write-Host "Return the USB drive to the development PC so it can import lab-response.json."
Write-Host "Then sign in locally as '$($manifest.lab_user)', open PowerShell, and run:"
Write-Host "  & '$stagedSkill\scripts\Initialize-OmpLabUser.ps1'"
