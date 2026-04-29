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

Start/restart can refresh the Windows portproxy for WSL SSH when run from an
Administrator PowerShell. Other commands work without elevation.
#>

[CmdletBinding()]
param(
	[ValidateSet("status", "start", "stop", "restart", "shell", "ssh", "ip", "update")]
	[string]$Command = "status",
	[string]$Distro = "",
	[string]$User = "",
	[int]$SshPort = 2222
)

$ErrorActionPreference = "Stop"

function Info($m) { Write-Host "==> $m"  -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[ok]  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!]   $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[err] $m" -ForegroundColor Red; exit 1 }

$PortProxyRuleName = "Homelab-WSL-SSH-$SshPort"
$KeepAliveName = "homelab-keepalive"
$KeepAliveUnit = "homelab-keepalive.service"

function Test-IsAdmin {
	$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
	$principal = [Security.Principal.WindowsPrincipal]::new($identity)
	return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

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

function Test-KeepAlive {
	$null = (wsl.exe -d $Distro --exec sh -lc "pgrep -f '^$KeepAliveName ' >/dev/null") 2>$null
	return ($LASTEXITCODE -eq 0)
}

function Test-WindowsKeepAlive {
	$needle = "-d $Distro --exec sleep infinity"
	$proc = Get-CimInstance Win32_Process -Filter "name='wsl.exe'" -ErrorAction SilentlyContinue |
		Where-Object { $_.CommandLine -like "*$needle*" } |
		Select-Object -First 1
	return [bool]$proc
}

function Start-WindowsKeepAlive {
	if (Test-WindowsKeepAlive) {
		Ok "Windows keepalive process is running"
		return
	}

	$wslPath = Join-Path $env:WINDIR "System32\wsl.exe"
	$command = "$wslPath -d $Distro --exec sleep infinity"
	$result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $command }
	if ($result.ReturnValue -ne 0) {
		Warn "Could not start Windows keepalive process via WMI (code $($result.ReturnValue))."
		return
	}
	Start-Sleep -Milliseconds 500
	if (Test-WindowsKeepAlive) {
		Ok "Windows keepalive process is running"
	} else {
		Warn "Windows keepalive process started but was not found."
	}
}

function Stop-WindowsKeepAlive {
	$needle = "-d $Distro --exec sleep infinity"
	Get-CimInstance Win32_Process -Filter "name='wsl.exe'" -ErrorAction SilentlyContinue |
		Where-Object { $_.CommandLine -like "*$needle*" } |
		ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate -ErrorAction SilentlyContinue | Out-Null }
}

function Remove-StaleKeepAliveTask {
	$taskName = "Homelab-KeepAlive-$Distro"
	$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
	if ($task) {
		Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
	}
}

function Ensure-KeepAliveUnit {
	$unitScript = @'
cat >/etc/systemd/system/homelab-keepalive.service <<'EOF'
[Unit]
Description=Keep WSL homelab resident for SSH access
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -lc 'exec -a homelab-keepalive sleep infinity'
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now homelab-keepalive.service
'@
	Invoke-WslChecked `
		-WslArgs @("-d", $Distro, "-u", "root", "--exec", "sh", "-lc", $unitScript) `
		-FailureMessage "Failed to enable WSL keepalive service."
}

function Ensure-KeepAlive {
	Start-WindowsKeepAlive
	if (Test-KeepAlive) {
		Ok "keepalive process is running"
		return
	}

	Remove-StaleKeepAliveTask
	Info "Starting WSL keepalive systemd service"
	Ensure-KeepAliveUnit
	for ($i = 0; $i -lt 20; $i++) {
		Start-Sleep -Milliseconds 500
		if (Test-KeepAlive) {
			Ok "keepalive process is running"
			return
		}
	}
	Warn "Could not confirm keepalive process. WSL may stop when idle."
}

function Stop-KeepAlive {
	Stop-WindowsKeepAlive
	wsl.exe -d $Distro -u root --exec systemctl stop $KeepAliveUnit 2>$null
}

function Get-WslIpv4 {
	$raw = (wsl.exe -d $Distro --exec hostname -I) 2>$null
	if ($LASTEXITCODE -ne 0) { return "" }
	$ips = ($raw -replace "`0", " ") -split "\s+" |
		ForEach-Object { $_.Trim() } |
		Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -ne "127.0.0.1" -and $_ -notlike "172.17.*" }
	return ($ips | Select-Object -First 1)
}

function Ensure-WslSshPortProxy {
	$wslIp = Get-WslIpv4
	if (-not $wslIp) {
		Warn "Could not determine the WSL IPv4 address; portproxy was not updated."
		return
	}

	if (-not (Test-IsAdmin)) {
		Warn "Run start/restart from Administrator PowerShell to refresh Windows portproxy for WSL SSH."
		Write-Host "      Needed rule: 0.0.0.0:$SshPort -> ${wslIp}:$SshPort"
		return
	}

	Info "Refreshing Windows portproxy for WSL SSH"
	& netsh.exe interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$SshPort *> $null
	& netsh.exe interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$SshPort connectaddress=$wslIp connectport=$SshPort *> $null
	if ($LASTEXITCODE -ne 0) { Die "Failed to add portproxy rule for WSL SSH." }

	$existingRule = Get-NetFirewallRule -DisplayName $PortProxyRuleName -ErrorAction SilentlyContinue
	if (-not $existingRule) {
		New-NetFirewallRule -DisplayName $PortProxyRuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $SshPort -Profile Any | Out-Null
	} else {
		Set-NetFirewallRule -DisplayName $PortProxyRuleName -Enabled True -Profile Any | Out-Null
	}
	Ok "WSL SSH forwarded on Windows port $SshPort -> ${wslIp}:$SshPort"
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
	Ensure-KeepAlive
	Ensure-WslSshPortProxy
}

function Stop-Instance {
	Ensure-Wsl
	Info "Stopping WSL distro '$Distro'"
	Stop-KeepAlive
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
		$wslIp = Get-WslIpv4
		if ($wslIp) {
			Write-Host ""
			Write-Host "WSL SSH: localhost:$SshPort -> ${wslIp}:$SshPort"
		}
	} else {
		Write-Host ""
		Write-Host "Start it with:"
		Write-Host "  hl start"
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
