[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TransferRoot,
    [string]$AllowedRemoteAddress,
    [ValidatePattern('^[A-Za-z0-9._-]{1,20}$')][string]$LabUser = 'omp-lab',
    [string]$ProjectRepository,
    [string]$KeyPath = (Join-Path $HOME '.ssh\omp_windows_lab'),
    [string]$SshAlias
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RemoteLab.Common.ps1')

$root = Resolve-RemoteLabTransferRoot -TransferRoot $TransferRoot
if (-not $AllowedRemoteAddress) {
    $addresses = @(Get-RemoteLabAddresses)
    if ($addresses.Count -ne 1) {
        throw "Could not choose one controller address safely. Available addresses: $($addresses -join ', '). Re-run with -AllowedRemoteAddress."
    }
    $AllowedRemoteAddress = $addresses[0]
}

$privateKey = $KeyPath
$publicKey = "$KeyPath.pub"
if (-not (Test-Path -LiteralPath $privateKey)) {
    if (-not $PSCmdlet.ShouldProcess($privateKey, 'Generate dedicated Ed25519 lab key')) { return }
    New-Item -Path (Split-Path -Parent $privateKey) -ItemType Directory -Force | Out-Null
    & ssh-keygen -q -t ed25519 -N '' -f $privateKey -C "OMP remote lab from $env:COMPUTERNAME"
    if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen failed.' }
}
if (-not (Test-Path -LiteralPath $publicKey)) { throw "Public key '$publicKey' is missing." }

$transferId = [guid]::NewGuid()
$bundle = Join-Path $root "OMP-Remote-Lab\$($transferId.ToString())"
New-Item -Path (Join-Path $bundle 'scripts') -ItemType Directory -Force | Out-Null
New-Item -Path (Join-Path $bundle 'skill') -ItemType Directory -Force | Out-Null

$skillRoot = Split-Path -Parent $PSScriptRoot
Copy-Item -LiteralPath $publicKey -Destination (Join-Path $bundle 'controller.pub') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Enable-OmpLabAccess.ps1') -Destination (Join-Path $bundle 'scripts') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Initialize-LabPc.ps1') -Destination (Join-Path $bundle 'scripts') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Initialize-OmpLabUser.ps1') -Destination (Join-Path $bundle 'scripts') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RemoteLab.Common.ps1') -Destination (Join-Path $bundle 'scripts') -Force
Copy-Item -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Destination (Join-Path $bundle 'skill') -Force
Copy-Item -LiteralPath (Join-Path $skillRoot 'references') -Destination (Join-Path $bundle 'skill') -Recurse -Force
Copy-Item -LiteralPath $PSScriptRoot -Destination (Join-Path $bundle 'skill') -Recurse -Force

$manifest = [ordered]@{
    schema_version = '1.0'
    transfer_id = $transferId.ToString()
    created_at_utc = [DateTimeOffset]::UtcNow.ToString('O')
    controller = New-RemoteLabDeviceRecord -Role dev_pc -State transfer_prepared -TransferId $transferId -ProjectRepository $ProjectRepository -Checks @{ public_key_created = $true; transfer_prepared = $true }
    allowed_remote_address = $AllowedRemoteAddress
    lab_user = $LabUser
    project_repository = $ProjectRepository
    requested_ssh_alias = $SshAlias
    public_key_file = 'controller.pub'
    private_key_included = $false
}
Write-RemoteLabJson -Path (Join-Path $bundle 'manifest.json') -Value $manifest
Update-RemoteLabRegistryDevice -Device $manifest.controller -AsController | Out-Null

Write-Host "Development PC initialized. Transfer bundle: $bundle"
Write-Host 'The private key stayed on this device.'
Write-Host 'Safely eject the USB drive, connect it to the lab PC, start OMP there, and say: initialize this device as a lab PC using the connected USB drive.'
