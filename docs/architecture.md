# Architecture

## Layers

```
+--------------------------------------------------------------+
| Windows 11 Home (host)                                       |
|   - gaming, normal desktop                                   |
|   - Tailscale Windows client (primary tailnet node)          |
|   - Hyper-V / WSL2 virtualization layer                      |
|                                                              |
|   +------------------------------------------------------+   |
|   | WSL2 lightweight VM (utility VM)                     |   |
|   |   - shared kernel image, managed by Windows          |   |
|   |   - default NAT networking, reached through portproxy |   |
|   |                                                      |   |
|   |   +------------------------------------------+       |   |
|   |   | Ubuntu distro                            |       |   |
|   |   |   - systemd PID 1                        |       |   |
|   |   |   - sshd (port 2222, key auth only)      |       |   |
|   |   |   - dockerd (Engine, native install)     |       |   |
|   |   |   - optional tailscaled (fallback path)  |       |   |
|   |   |   - VM config in /opt/homelab           |       |   |
|   |   |   - VM state in /srv/homelab            |       |   |
|   |   +------------------------------------------+       |   |
|   +------------------------------------------------------+   |
+--------------------------------------------------------------+
```

## Boot flow

1. Windows boots; nothing WSL-related runs yet.
2. `.\homelab.ps1 start` starts the utility VM, launches a hidden
   `homelab-keepalive` process, and refreshes Windows portproxy for SSH.
3. The utility VM boots the Ubuntu distro under systemd, because
   `/etc/wsl.conf` has `[boot] systemd=true`.
4. systemd starts enabled units: `ssh`, `docker`, optionally `tailscaled`.
5. The custom MOTD runs `hl status --motd` for a compact health snapshot.
6. The shell stays normal. Run `tm <name>` for a persistent tmux session
   or `hl dash` for the monitoring dashboard.

After idle, WSL2 will gradually return RAM to Windows because of
`autoMemoryReclaim=gradual` in `.wslconfig`. Containers stay running
inside the VM unless explicitly stopped.

## Traffic flow examples

### SSH from phone via Termius

```
phone (Termius) --[WireGuard tunnel]--> tailscaled (Windows)
   --[Windows :2222 portproxy]--> sshd (WSL Ubuntu)
   --[bash + optional tmux]-->  normal user shell
```

### Ollama API call from laptop

```
laptop (curl) --[WireGuard]--> tailscaled (Windows)
   --[explicit Windows/WSL forwarding]--> docker port-forward
   --[container :11434]--> ollama --[NVIDIA toolkit]--> RTX 4060 Ti
```

The Ollama port is bound to `127.0.0.1:11434` on the WSL side by
default. Expose services deliberately, either with a Windows portproxy,
Tailscale Serve, or by installing Tailscale inside WSL for that service.
By default nothing is exposed to the public internet.

### Docker host -> container -> GPU

```
shell (/opt/homelab) -> docker compose up -d
dockerd --[unix socket]--> containerd --[runc]--> ollama container
   --[NVIDIA Container Toolkit]--> /dev/nvidia* --[CUDA-on-WSL]--> GPU
```

CUDA-on-WSL means the GPU driver lives on the Windows side; the
container sees a synthetic `nvidia-smi` that talks to the Windows
driver via the Microsoft GPU paravirtualization shim. There is no
separate Linux NVIDIA driver to install inside WSL.

## What lives where

| Concern | Location | In repo? |
| --- | --- | --- |
| `.wslconfig` | `%UserProfile%\.wslconfig` (Windows) | yes (`wsl/wslconfig.example`) |
| `/etc/wsl.conf` | inside Ubuntu | yes (`wsl/wsl.conf`) |
| dotfiles | `~/.tmux.conf` etc | yes (`dotfiles/`, optional per user) |
| sshd config | `/etc/ssh/sshd_config` | edited in place by `00-bootstrap.sh` |
| user authorized keys | `~/.ssh/authorized_keys` | no (manual paste) |
| project repos | user-chosen locations under `/home/<user>` | no |
| service data | `/srv/homelab/data/<name>` and named docker volumes | no |
| model weights | docker volume `ollama-data` (or `/srv/homelab/models/`) | no |
| backups | `/srv/homelab/backups/` | no |
