#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^ssh-ed25519\s+')][string]$PublicKey,
    [Parameter(Mandatory)][string]$AllowedRemoteAddress,
    [ValidatePattern('^[A-Za-z0-9._-]{1,20}$')][string]$LabUser = 'omp-lab',
    [securestring]$InitialPassword
)

$ErrorActionPreference = 'Stop'
$firewallRule = 'OMP-Windows-Lab-SSH'

$capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
if ($capability.State -ne 'Installed' -and $PSCmdlet.ShouldProcess('OpenSSH Server', 'Install Windows capability')) {
    Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
}

if (-not (Get-LocalUser -Name $LabUser -ErrorAction SilentlyContinue)) {
    if (-not $InitialPassword) {
        $InitialPassword = Read-Host "Initial password for local account $LabUser" -AsSecureString
    }
    if ($PSCmdlet.ShouldProcess($LabUser, 'Create dedicated local lab account')) {
        New-LocalUser -Name $LabUser -Password $InitialPassword -Description 'Dedicated OMP Windows lab account' | Out-Null
    }
}

$adminMembers = Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop
if (-not ($adminMembers.Name -match "\\$([regex]::Escape($LabUser))$")) {
    if ($PSCmdlet.ShouldProcess($LabUser, 'Add to local Administrators')) {
        Add-LocalGroupMember -Group 'Administrators' -Member $LabUser
    }
}

$sshRoot = Join-Path $env:ProgramData 'ssh'
New-Item -Path $sshRoot -ItemType Directory -Force | Out-Null
$keyPath = Join-Path $sshRoot 'administrators_authorized_keys'
$normalizedKey = $PublicKey.Trim()
$existingKeys = if (Test-Path $keyPath) { Get-Content $keyPath } else { @() }
if ($existingKeys -notcontains $normalizedKey -and $PSCmdlet.ShouldProcess($keyPath, 'Add dedicated public key')) {
    Add-Content -Path $keyPath -Value $normalizedKey -Encoding ascii
}
if (Test-Path $keyPath) {
    icacls $keyPath /inheritance:r /grant:r 'SYSTEM:F' '*S-1-5-32-544:F' | Out-Null
}

Get-NetFirewallRule -Name $firewallRule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
if ($PSCmdlet.ShouldProcess($firewallRule, "Allow SSH only from $AllowedRemoteAddress")) {
    New-NetFirewallRule -Name $firewallRule -DisplayName 'OMP Windows Lab SSH' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 -RemoteAddress $AllowedRemoteAddress -Profile Domain,Private | Out-Null
}

Set-Service sshd -StartupType Automatic
Start-Service sshd
& "$env:WINDIR\System32\OpenSSH\sshd.exe" -t

Write-Host "OpenSSH is running. Test key login from a second terminal before disabling password authentication."
Write-Host "Firewall rule $firewallRule permits TCP 22 only from $AllowedRemoteAddress."
