<#
01-tailscale.ps1 -- install Tailscale on the Windows host.

Idempotent. Run in an Administrator PowerShell. Uses winget if available,
otherwise downloads the official MSI.
#>

[CmdletBinding()]
param(
	[switch]$NoStart
)

$ErrorActionPreference = "Stop"

function Info($m) { Write-Host "==> $m"  -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[ok]  $m" -ForegroundColor Green }
function Die($m)  { Write-Host "[err] $m" -ForegroundColor Red; exit 1 }
function Assert-LastExit($m) {
	if ($LASTEXITCODE -ne 0) { Die $m }
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Die "Run this script in an Administrator PowerShell." }

if (Get-Command tailscale -ErrorAction SilentlyContinue) {
	$ver = (tailscale version | Select-Object -First 1)
	Ok "Tailscale already installed: $ver"
} else {
	if (Get-Command winget -ErrorAction SilentlyContinue) {
		Info "Installing Tailscale via winget"
		winget install --id Tailscale.Tailscale -e --accept-source-agreements --accept-package-agreements
		Assert-LastExit "winget failed to install Tailscale."
	} else {
		$msiUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest.msi"
		$msi    = Join-Path $env:TEMP "tailscale-setup.msi"
		Info "Downloading Tailscale installer to $msi"
		Invoke-WebRequest -Uri $msiUrl -OutFile $msi -UseBasicParsing
		Info "Running silent install"
		$p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart" -Wait -PassThru
		if ($p.ExitCode -ne 0) { Die "Tailscale MSI install failed with exit code $($p.ExitCode)." }
	}
	Ok "Tailscale installed."
}

if (-not $NoStart) {
	Write-Host ""
	Write-Host "Bring up the tunnel manually:" -ForegroundColor Cyan
	Write-Host "    tailscale up --operator $env:USERNAME"
	Write-Host "Then verify with:"
	Write-Host "    tailscale status"
	Write-Host ""
}
