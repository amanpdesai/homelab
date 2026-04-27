<#
instance.ps1 -- Windows-side WSL homelab instance control.

Usage:
  .\scripts\windows\instance.ps1 status
  .\scripts\windows\instance.ps1 start
  .\scripts\windows\instance.ps1 stop
  .\scripts\windows\instance.ps1 restart
  .\scripts\windows\instance.ps1 shell
  .\scripts\windows\instance.ps1 ssh
  .\scripts\windows\instance.ps1 update

This script does not require Administrator PowerShell. It controls the WSL
distro from the Windows host and keeps normal SSH/tmux behavior unchanged.
#>

[CmdletBinding()]
param(
	[ValidateSet("status", "start", "stop", "restart", "shell", "ssh", "ip", "update")]
	[string]$Command = "status",
	[string]$Distro = "",
	[string]$User = "",
	[int]$SshPort = 22
)

$ErrorActionPreference = "Stop"

function Info($m) { Write-Host "==> $m"  -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[ok]  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!]   $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[err] $m" -ForegroundColor Red; exit 1 }

function Get-DistroNames {
	$raw = (wsl.exe -l -q) 2>$null
	if ($LASTEXITCODE -ne 0) {
		Die "Failed to list WSL distros. If WSL reports Virtual Machine Platform is required, run scripts\windows\00-prereqs.ps1 as Administrator and reboot."
	}
	if (-not $raw) { return @() }
	return ($raw -replace "`0", "") -split "`r?`n" |
		ForEach-Object { $_.Trim() } |
		Where-Object { $_ }
}

function Invoke-WslChecked {
	param(
		[string[]]$WslArgs,
		[string]$FailureMessage
	)
	wsl.exe @WslArgs
	if ($LASTEXITCODE -ne 0) { Die $FailureMessage }
}

function Resolve-Distro {
	$distros = @(Get-DistroNames)
	if ($distros.Count -eq 0) {
		Die "No WSL distros found. Run scripts\windows\00-prereqs.ps1 from an Administrator PowerShell first."
	}
	if ($Distro) {
		if ($distros -contains $Distro) { return $Distro }
		Die "WSL distro '$Distro' not found. Installed distros: $($distros -join ', ')"
	}
	foreach ($candidate in @("Ubuntu-24.04", "Ubuntu")) {
		if ($distros -contains $candidate) { return $candidate }
	}
	$firstLinux = $distros | Where-Object { $_ -notmatch '^docker-desktop' } | Select-Object -First 1
	if ($firstLinux) { return $firstLinux }
	Die "No usable Linux WSL distro found. Installed distros: $($distros -join ', ')"
}

function Ensure-Wsl {
	if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
		Die "wsl.exe not found. Run scripts\windows\00-prereqs.ps1 from an Administrator PowerShell first."
	}
	$script:Distro = Resolve-Distro
}

function Get-DistroState {
	$raw = (wsl.exe -l -v) 2>$null
	if ($LASTEXITCODE -ne 0) { return "Unknown" }
	$lines = ($raw -replace "`0", "") -split "`r?`n" |
		ForEach-Object { $_.Trim().TrimStart("*").Trim() } |
		Where-Object { $_ }
	foreach ($line in $lines) {
		if ($line -match "^$([regex]::Escape($Distro))\s+(\S+)") {
			return $Matches[1]
		}
	}
	return "Unknown"
}

function Start-Instance {
	Ensure-Wsl
	Info "Starting WSL distro '$Distro'"
	Invoke-WslChecked -WslArgs @("-d", $Distro, "--exec", "sh", "-lc", "true") -FailureMessage "Failed to start '$Distro'"
	Ok "'$Distro' is started"
}

function Stop-Instance {
	Ensure-Wsl
	Info "Stopping WSL distro '$Distro'"
	Invoke-WslChecked -WslArgs @("--terminate", $Distro) -FailureMessage "Failed to stop '$Distro'"
	Ok "'$Distro' is stopped"
}

function Show-Status {
	Ensure-Wsl
	$state = Get-DistroState
	Write-Host "Distro: $Distro"
	Write-Host "State:  $state"
	if ($state -eq "Running") {
		Write-Host ""
		wsl.exe -d $Distro --exec sh -lc "hostname; uptime -p; command -v hl >/dev/null 2>&1 && hl status --plain --no-services || true"
	} else {
		Write-Host ""
		Write-Host "Start it with:"
		Write-Host "  .\homelab.ps1 start"
	}
}

function Show-Ip {
	Ensure-Wsl
	Invoke-WslChecked -WslArgs @("-d", $Distro, "--exec", "sh", "-lc", "true") -FailureMessage "Failed to start '$Distro'"
	Invoke-WslChecked -WslArgs @("-d", $Distro, "--exec", "sh", "-lc", "hostname -I | awk '{print `$1}'") -FailureMessage "Failed to read '$Distro' IP address"
}

function Open-Shell {
	Ensure-Wsl
	wsl.exe -d $Distro
}

function Open-Ssh {
	Ensure-Wsl
	Start-Instance
	$target = "localhost"
	if ($User) { $target = "$User@$target" }
	ssh.exe -p $SshPort $target
}

function Update-Instance {
	Ensure-Wsl
	Info "Updating WSL kernel"
	wsl.exe --update
	if ($LASTEXITCODE -ne 0) { Die "wsl --update failed." }
	Ok "WSL kernel update complete"

	Start-Instance
	Info "Updating packages and services inside '$Distro'"
	Invoke-WslChecked -WslArgs @("-d", $Distro, "--exec", "sh", "-lc", "if command -v hl >/dev/null 2>&1; then hl update; else sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y; fi") -FailureMessage "In-distro update failed."
}

switch ($Command) {
	"status"  { Show-Status }
	"start"   { Start-Instance }
	"stop"    { Stop-Instance }
	"restart" { Stop-Instance; Start-Instance }
	"shell"   { Open-Shell }
	"ssh"     { Open-Ssh }
	"ip"      { Show-Ip }
	"update"  { Update-Instance }
}
