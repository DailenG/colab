[CmdletBinding(SupportsShouldProcess)]
param([string]$StagedSkillPath = (Join-Path $env:ProgramData 'OmpRemoteLab\remote-windows-lab'))

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath (Join-Path $StagedSkillPath 'SKILL.md'))) { throw "Staged skill was not found at '$StagedSkillPath'." }
$destination = Join-Path $HOME '.omp\agent\skills\remote-windows-lab'
New-Item -Path (Split-Path -Parent $destination) -ItemType Directory -Force | Out-Null
Copy-Item -LiteralPath $StagedSkillPath -Destination $destination -Recurse -Force

$omp = Get-Command omp -ErrorAction SilentlyContinue
if ($omp) {
    & omp config set computer.enabled true
    & omp config set computer.display all
    & omp config set computer.maxWidth 1920
    & omp config set computer.maxHeight 1200
    & omp config set browser.enabled true
    & omp config set browser.relay true
    & omp config set tools.approvalMode write
    $ompConfigured = $true
} else {
    $ompConfigured = $false
}

$statePath = Join-Path $env:ProgramData 'OmpRemoteLab\device-state.json'
if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $state.state = if ($ompConfigured) { 'ready' } else { 'omp_pending' }
    $state.updated_at_utc = [DateTimeOffset]::UtcNow.ToString('O')
    $state.checks.omp_user_setup = $ompConfigured
    $temporary = "$statePath.tmp"
    $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $statePath -Force
}

if ($ompConfigured) {
    Write-Host "OMP and the remote-windows-lab skill are configured for $env:USERNAME. Restart OMP, then ask it to show remote lab state."
} else {
    Write-Host 'The skill was installed, but OMP is not on PATH. Install OMP, rerun this script, and then restart OMP.'
}
Write-Host 'Install or reload the OMP browser extension manually in a dedicated Edge lab profile; that browser action is intentionally not automated.'
