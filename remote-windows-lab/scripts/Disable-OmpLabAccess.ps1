#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidatePattern('^[A-Za-z0-9._-]{1,20}$')][string]$LabUser = 'omp-lab',
    [string]$PublicKey,
    [switch]$RemoveLabUser
)

$ErrorActionPreference = 'Stop'
Get-NetFirewallRule -Name 'OMP-Windows-Lab-SSH' -ErrorAction SilentlyContinue | Remove-NetFirewallRule

$keyPath = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
if ($PublicKey -and (Test-Path $keyPath) -and $PSCmdlet.ShouldProcess($keyPath, 'Remove specified lab public key')) {
    $target = $PublicKey.Trim()
    @(Get-Content $keyPath | Where-Object { $_.Trim() -ne $target }) | Set-Content $keyPath -Encoding ascii
    icacls $keyPath /inheritance:r /grant:r 'SYSTEM:F' '*S-1-5-32-544:F' | Out-Null
}

if ($RemoveLabUser -and (Get-LocalUser -Name $LabUser -ErrorAction SilentlyContinue) -and $PSCmdlet.ShouldProcess($LabUser, 'Remove dedicated local lab account')) {
    Remove-LocalUser -Name $LabUser
}

Write-Host 'Removed the OMP lab firewall rule. OpenSSH Server and unrelated SSH configuration were left intact.'
