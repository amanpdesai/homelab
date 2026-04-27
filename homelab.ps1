<#
Root convenience wrapper for Windows-side homelab instance control.

Examples:
  .\homelab.ps1 status
  .\homelab.ps1 start
  .\homelab.ps1 stop
  .\homelab.ps1 restart
  .\homelab.ps1 shell
  .\homelab.ps1 ssh -User <wsl-user>
  .\homelab.ps1 update
#>

[CmdletBinding()]
param(
	[Parameter(Position = 0)]
	[ValidateSet("status", "start", "stop", "restart", "shell", "ssh", "ip", "update")]
	[string]$Command = "status",
	[string]$Distro = "",
	[string]$User = "",
	[int]$SshPort = 22
)

$script = Join-Path $PSScriptRoot "scripts\windows\instance.ps1"
& $script -Command $Command -Distro $Distro -User $User -SshPort $SshPort
