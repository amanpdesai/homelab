# Inventory

Living snapshot. Update whenever the underlying state changes (driver
upgrade, distro reinstall, hardware swap). Use git history to compare
across time.

Last updated: 2026-04-26.

## Hardware

| Component | Spec |
| --- | --- |
| CPU       | Intel Core i5-13600K (14 cores, 20 threads) |
| RAM       | 32 GB |
| GPU       | NVIDIA GeForce RTX 4060 Ti, 8188 MiB VRAM |
| Storage   | 1 TB SSD (single drive) |
| Use case  | Hybrid: gaming + dev/server |

## Software

| Layer | Version |
| --- | --- |
| Host OS         | Windows 11 Home, build 26200 |
| NVIDIA driver   | 591.86 |
| CUDA (reported) | 13.1 |
| WSL kernel      | from `wsl --update`, kept current |
| Default distro  | Ubuntu (target Ubuntu-24.04) |
| Docker          | docker-ce (native, installed via `02-install-docker.sh`) |
| Tailscale (host)| latest stable, installed via winget or MSI |

## Pre-existing state at scaffold time

Discovered when `wsl -l -v` was first run on 2026-04-26:

- `Ubuntu` distro present, stopped, version 2.
- `docker-desktop` distro present, stopped (Docker Desktop's helper).
  **Removed by user on 2026-04-26 (Docker Desktop uninstalled).**

The plan is to keep the `Ubuntu` distro if its version and user state
are healthy, otherwise unregister and start fresh on Ubuntu-24.04 via
`scripts\windows\00-prereqs.ps1`.

## Required Windows configuration

These must be set for the homelab to work; verify after any major
Windows reinstall.

| Setting | Where | Required value |
| --- | --- | --- |
| Virtualization              | BIOS / UEFI            | Enabled (VT-x / AMD-V) |
| Virtual Machine Platform    | Optional Features      | Enabled |
| Windows Subsystem for Linux | Optional Features      | Enabled |
| Hyper-V hypervisor          | implicitly on with VMP | Enabled |
| Time sync                   | Windows                | NTP enabled (WSL inherits) |

Verify:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform | Format-List State
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux | Format-List State
Get-CimInstance Win32_Processor | Select-Object VirtualizationFirmwareEnabled, SecondLevelAddressTranslationExtensions
```

## Network

- Tailnet: amanpdesai's tailnet (Tailscale account).
- MagicDNS: enabled (default).
- Tailscale ACLs: default-allow personal devices; tighten if more nodes
  are added (write tags into ACL, advertise via `--advertise-tags`).
- Public exposure: none. No router port forwards. No DDNS.

## Filesystem layout (canonical)

```
~/srv/
  homelab/         this repo (git tracked)
  projects/        per-project git repos
  models/          gitignored, model weights
  data/            gitignored, service data (or use named docker volumes)
  backups/         gitignored, local snapshots
  logs/
```

## Repo

- URL: https://github.com/amanpdesai/homelab (private)
- Local clone at scaffold time: `C:\Users\amanp\homelab`
- Target clone path inside WSL: `~/srv/homelab`

## Out of scope (intentionally)

- Public-facing services. We have no domain plumbing here. Add Caddy
  plus Tailscale Funnel later if needed.
- Kubernetes. Compose is enough for a single-host setup.
- Multi-user support. Single-user box.
- HA / clustering. Not the goal.
