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

function Install-HlProfileBlock {
	param([string]$ProfilePath)

	$profileDir = Split-Path -Parent $ProfilePath
	if ($profileDir) {
		New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
	}

	$existing = ""
	if (Test-Path $ProfilePath) {
		$existing = Get-Content -Raw -Path $ProfilePath
	}

	$pattern = "(?ms)^$([regex]::Escape($start)).*?^$([regex]::Escape($end))\r?\n?"
	if ($existing -match $pattern) {
		$updated = [regex]::Replace($existing, $pattern, $block + [Environment]::NewLine)
	} elseif ($existing.Trim()) {
		$updated = $existing.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block + [Environment]::NewLine
	} else {
		$updated = $block + [Environment]::NewLine
	}

	Set-Content -Path $ProfilePath -Value $updated -Encoding UTF8
	Write-Host "[ok] installed hl helper in $ProfilePath" -ForegroundColor Green
}

$documents = [Environment]::GetFolderPath("MyDocuments")
$profilePaths = @(
	(Join-Path $documents "WindowsPowerShell\profile.ps1"),
	(Join-Path $documents "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"),
	(Join-Path $documents "PowerShell\profile.ps1"),
	(Join-Path $documents "PowerShell\Microsoft.PowerShell_profile.ps1")
) | Select-Object -Unique

foreach ($profilePath in $profilePaths) {
	Install-HlProfileBlock -ProfilePath $profilePath
}

Write-Host "Open a new PowerShell session, then run: hl status" -ForegroundColor Cyan
