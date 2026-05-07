<#
Install a Windows command shim and PowerShell helper so `hl start`, `hl stop`,
and `hl status` control the homelab WSL instance from SSH, cmd.exe, and
PowerShell prompts.
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

function Add-UserPath {
	param([string]$PathToAdd)

	$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
	$parts = @()
	if ($userPath) {
		$parts = $userPath -split ";" | Where-Object { $_ }
	}
	$alreadyPresent = $parts | Where-Object {
		$_.TrimEnd("\") -ieq $PathToAdd.TrimEnd("\")
	} | Select-Object -First 1

	if (-not $alreadyPresent) {
		$newPath = (@($parts) + $PathToAdd) -join ";"
		[Environment]::SetEnvironmentVariable("Path", $newPath, "User")
		Write-Host "[ok] added $PathToAdd to the user PATH" -ForegroundColor Green
	}

	$currentParts = $env:Path -split ";" | Where-Object { $_ }
	$currentPresent = $currentParts | Where-Object {
		$_.TrimEnd("\") -ieq $PathToAdd.TrimEnd("\")
	} | Select-Object -First 1
	if (-not $currentPresent) {
		$env:Path = (@($currentParts) + $PathToAdd) -join ";"
	}
}

function Install-HlCommandShim {
	$binDir = Join-Path $env:USERPROFILE "bin"
	New-Item -ItemType Directory -Force -Path $binDir | Out-Null

	$shimPath = Join-Path $binDir "hl.cmd"
	$shim = @"
@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$homelab" %*
"@
	Set-Content -Path $shimPath -Value $shim -Encoding ASCII
	Add-UserPath -PathToAdd $binDir
	Write-Host "[ok] installed hl command shim in $shimPath" -ForegroundColor Green
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

Install-HlCommandShim

Write-Host "Open a new shell or SSH session, then run: hl status" -ForegroundColor Cyan
