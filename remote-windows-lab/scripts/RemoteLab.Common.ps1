Set-StrictMode -Version Latest

function Get-RemoteLabRegistryPath {
    if ($env:OMP_REMOTE_LAB_REGISTRY) { return $env:OMP_REMOTE_LAB_REGISTRY }
    Join-Path $HOME '.omp\remote-windows-lab\devices.json'
}

function Read-RemoteLabJson {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-RemoteLabJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $directory = Split-Path -Parent $Path
    New-Item -Path $directory -ItemType Directory -Force | Out-Null
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-RemoteLabAddresses {
    @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
        Sort-Object InterfaceMetric, SkipAsSource |
        Select-Object -ExpandProperty IPAddress -Unique)
}

function Get-RemoteLabRemovableRoots {
    @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceID } |
        ForEach-Object { "$($_.DeviceID)\" })
}

function Resolve-RemoteLabTransferRoot {
    param([string]$TransferRoot)
    if ($TransferRoot) {
        if (-not (Test-Path -LiteralPath $TransferRoot)) { throw "Transfer path '$TransferRoot' does not exist." }
        return (Resolve-Path -LiteralPath $TransferRoot).Path
    }
    $removable = @(Get-RemoteLabRemovableRoots)
    if ($removable.Count -eq 0) {
        throw 'No removable drive was found. Connect a USB thumb drive, wait for Windows to mount it, and run the initialization request again; or provide -TransferRoot explicitly.'
    }
    if ($removable.Count -gt 1) {
        throw "Multiple removable drives were found: $($removable -join ', '). Re-run with -TransferRoot and the intended drive."
    }
    $removable[0]
}

function New-RemoteLabDeviceRecord {
    param(
        [Parameter(Mandatory)][ValidateSet('dev_pc','lab_pc')][string]$Role,
        [Parameter(Mandatory)][ValidateSet('discovered','transfer_prepared','bootstrap_applied','ssh_verified','omp_pending','ready','retired','error')][string]$State,
        [guid]$DeviceId = [guid]::NewGuid(),
        [guid]$TransferId = [guid]::Empty,
        [string]$SshAlias,
        [string]$LabUser,
        [string]$ProjectRepository,
        [hashtable]$Checks = @{},
        [string[]]$Notes = @()
    )
    [ordered]@{
        device_id = $DeviceId.ToString()
        hostname = $env:COMPUTERNAME
        role = $Role
        state = $State
        updated_at_utc = [DateTimeOffset]::UtcNow.ToString('O')
        addresses = @(Get-RemoteLabAddresses)
        ssh_alias = $SshAlias
        lab_user = $LabUser
        project_repository = $ProjectRepository
        transfer_id = if ($TransferId -eq [guid]::Empty) { $null } else { $TransferId.ToString() }
        checks = $Checks
        notes = @($Notes)
    }
}

function Update-RemoteLabRegistryDevice {
    param([Parameter(Mandatory)]$Device, [switch]$AsController)
    $path = Get-RemoteLabRegistryPath
    $registry = Read-RemoteLabJson -Path $path
    if (-not $registry) {
        $registry = [ordered]@{
            schema_version = '1.0'
            registry_id = [guid]::NewGuid().ToString()
            controller = $null
            devices = @()
            updated_at_utc = [DateTimeOffset]::UtcNow.ToString('O')
        }
    }
    if ($AsController) { $registry.controller = $Device }
    else {
        $devices = @($registry.devices | Where-Object { $_.device_id -ne $Device.device_id -and $_.hostname -ne $Device.hostname })
        $registry.devices = @($devices + $Device)
    }
    $registry.updated_at_utc = [DateTimeOffset]::UtcNow.ToString('O')
    Write-RemoteLabJson -Path $path -Value $registry
    $path
}
