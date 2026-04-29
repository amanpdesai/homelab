<#
Install a Windows PowerShell helper so `hl start`, `hl stop`, and
`hl status` control the homelab WSL instance from any PowerShell prompt.
#>

[CmdletBinding()]
param(
	[string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
	$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
	$RepoRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
}

$homelab = Join-Path $RepoRoot "homelab.ps1"
if (-not (Test-Path $homelab)) {
	throw "Missing homelab.ps1 at $homelab"
}

$profilePath = $PROFILE.CurrentUserAllHosts
if (-not $profilePath) {
	$profilePath = $PROFILE
}

$profileDir = Split-Path -Parent $profilePath
if ($profileDir) {
	New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
}

$start = "# >>> homelab hl helper >>>"
$end = "# <<< homelab hl helper <<<"
$escaped = $homelab.Replace("'", "''")
$block = @"
$start
function hl {
	& '$escaped' @args
}
$end
"@

$existing = ""
if (Test-Path $profilePath) {
	$existing = Get-Content -Raw -Path $profilePath
}

$pattern = "(?ms)^$([regex]::Escape($start)).*?^$([regex]::Escape($end))\r?\n?"
if ($existing -match $pattern) {
	$updated = [regex]::Replace($existing, $pattern, $block + [Environment]::NewLine)
} elseif ($existing.Trim()) {
	$updated = $existing.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block + [Environment]::NewLine
} else {
	$updated = $block + [Environment]::NewLine
}

Set-Content -Path $profilePath -Value $updated -Encoding UTF8
Write-Host "[ok] installed Windows PowerShell hl helper in $profilePath" -ForegroundColor Green
Write-Host "Open a new PowerShell session, then run: hl status" -ForegroundColor Cyan
