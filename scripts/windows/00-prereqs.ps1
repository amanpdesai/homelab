<#
00-prereqs.ps1 -- Windows-side homelab setup.

Idempotent. Run in an Administrator PowerShell.
- Verifies (and optionally installs) WSL2.
- Deploys .wslconfig to %UserProfile%.
- Updates the WSL kernel.
- Installs the target Ubuntu distro if missing.
- Restarts WSL so .wslconfig takes effect on next start.
#>

[CmdletBinding()]
param(
	[string]$Distro = "Ubuntu-24.04",
	[switch]$SkipWslInstall
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Info($m) { Write-Host "==> $m"  -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[ok]  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!]   $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[err] $m" -ForegroundColor Red; exit 1 }
function Assert-LastExit($m) {
	if ($LASTEXITCODE -ne 0) { Die $m }
}

# Require admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Die "Run this script in an Administrator PowerShell." }

# 1. Deploy .wslconfig
$wslConfigSrc = Join-Path $repoRoot "wsl\wslconfig.example"
$wslConfigDst = Join-Path $env:USERPROFILE ".wslconfig"
if (-not (Test-Path $wslConfigSrc)) { Die "Missing $wslConfigSrc" }

if (Test-Path $wslConfigDst) {
	$backup = "$wslConfigDst.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
	Copy-Item $wslConfigDst $backup
	Warn "Existing .wslconfig backed up to $backup"
}
Copy-Item $wslConfigSrc $wslConfigDst -Force
Ok "Deployed .wslconfig to $wslConfigDst"

# 2. WSL state and install
if (-not $SkipWslInstall) {
	Info "Checking WSL state..."

	$wslAvailable = $false
	if (Get-Command wsl -ErrorAction SilentlyContinue) {
		try {
			wsl --status | Out-Null
			$wslAvailable = ($LASTEXITCODE -eq 0)
		} catch {
			$wslAvailable = $false
		}
	}

	if (-not $wslAvailable) {
		Info "Installing WSL (no distro). A reboot will likely be required."
		wsl --install --no-distribution
		Assert-LastExit "WSL install failed."
		Warn "Reboot Windows, then re-run this script with -SkipWslInstall."
		exit 0
	}
	Ok "WSL is available."

	Info "Updating WSL kernel..."
	wsl --update | Out-Host
	Assert-LastExit "WSL kernel update failed."
	Ok "WSL kernel updated."

	$distros = @()
	$rawList = (wsl -l -q) 2>$null
	if ($rawList) {
		$distros = ($rawList -replace "`0","") -split "`r?`n" |
			ForEach-Object { $_.Trim() } |
			Where-Object { $_ }
	}

	if ($distros -notcontains $Distro) {
		Info "Installing distro: $Distro"
		wsl --install -d $Distro
		Assert-LastExit "Distro install failed: $Distro"
		Warn "Finish the Ubuntu first-run setup (create user plus password) before running 00-bootstrap.sh."
	} else {
		Ok "Distro '$Distro' already installed."
	}
}

# 3. Restart WSL so the new .wslconfig is read on next start
Info "Shutting down WSL so .wslconfig takes effect..."
wsl --shutdown
Assert-LastExit "wsl --shutdown failed."
Ok "Done."

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Open Ubuntu from the Start menu and finish first-run setup if needed."
Write-Host "  2. Inside WSL: clone this repo to /opt/homelab and run 'make bootstrap'."
Write-Host ""
