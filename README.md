# homelab

Personal home server / dev workstation configuration. Windows 11 host (gaming
plus normal desktop), WSL2 Ubuntu guest (development plus services), Tailscale
for private remote access.

This repo is the source of truth for `.wslconfig`, `/etc/wsl.conf`, dotfiles,
install scripts, and Docker compose stacks. It is a configuration repo, not a
data repo. Models, service data, and project code live outside it.

## Architecture

```
Windows 11 host                 gaming, normal desktop, Tailscale client
|
+-- WSL2 Ubuntu                 dev plus services, reachable over tailnet
    |-- sshd (systemd)          Termius / SSH entrypoint
    |-- tmux                    optional persistent sessions
    |-- docker engine           native; GPU passthrough via NVIDIA toolkit
    +-- /opt/homelab            VM configuration/control repo
    +-- /srv/homelab            VM service state, data, backups
```

Key choices:

- WSL2 with NAT plus a Windows `netsh portproxy` rule for WSL SSH. The
  `homelab.ps1 start` command refreshes the rule when WSL gets a new IP.
- Native Docker Engine inside WSL2, not Docker Desktop.
- Tailscale on the Windows host as the primary path. Tailscale inside WSL is
  optional and only needed if you want the VM to appear as its own tailnet node.
- SSH key authentication only. No password auth, no root login.

## Repo layout

```
homelab/
|-- wsl/
|   |-- wslconfig.example   deployed to %UserProfile%\.wslconfig
|   +-- wsl.conf            deployed to /etc/wsl.conf
|-- dotfiles/               tmux, bash, git, inputrc, ssh client config
|-- scripts/
|   |-- lib.sh              shared bash helpers
|   |-- windows/            PowerShell, run on Windows host as admin
|   +-- wsl/                bash, run inside WSL2 as your user
|-- docker/                 compose stacks, one directory per service
|-- docs/                   long-form docs: architecture, decisions, runbook, troubleshooting
|-- homelab.ps1             Windows-side start/stop/status wrapper
|-- Makefile                entry points for common ops
|-- .gitignore
+-- README.md
```

## VM Filesystem Layout

The homelab control plane is VM-level, not a personal project layout:

```
/opt/homelab/       this repo, installed once for the VM
/srv/homelab/
|-- data/           service data volumes
|-- models/         LLM weights and similar large blobs
|-- backups/        local snapshots
+-- logs/
```

Personal projects are intentionally out of scope. Put them directly under
`/home/<you>` or wherever you prefer; `homelab` does not manage them.

## Quickstart

Order matters. Each step is idempotent and safe to re-run.

### 1. Windows host (administrator PowerShell)

```powershell
git clone https://github.com/amanpdesai/homelab.git $env:USERPROFILE\homelab
cd $env:USERPROFILE\homelab

# WSL2 plus .wslconfig
.\scripts\windows\00-prereqs.ps1
# If WSL was just installed for the first time, reboot,
# then re-run with -SkipWslInstall.

# Tailscale on the Windows host
.\scripts\windows\01-tailscale.ps1
tailscale up

# Day-to-day WSL instance control from the repo root
.\homelab.ps1 status
.\homelab.ps1 start
.\homelab.ps1 stop
.\homelab.ps1 update
```

`start` and `restart` should be run from Administrator PowerShell when you
want WSL SSH reachable from another tailnet device; that lets the script keep
`0.0.0.0:2222 -> WSL:2222` current.
It also starts a hidden `homelab-keepalive` process inside WSL so the distro
stays online for SSH instead of idling out between sessions.

### 2. Inside WSL2 Ubuntu

```bash
sudo apt-get update && sudo apt-get install -y git make
sudo git clone https://github.com/amanpdesai/homelab.git /opt/homelab
sudo chown -R "$USER:$USER" /opt/homelab
cd /opt/homelab

make bootstrap       # base packages, sshd, /srv/homelab layout
make dotfiles        # symlink tmux, bash, git, inputrc, ssh config
make docker          # docker engine plus NVIDIA container toolkit
make tui             # install hl terminal manager and compact login MOTD
hl doctor            # verify readiness
# Optional, only if you want WSL to be its own Tailscale node:
# make tailscale-wsl
```

After `make bootstrap`, run `wsl --shutdown` from a Windows shell once so
that `/etc/wsl.conf`'s `systemd=true` takes effect.

## Remote access via Termius

1. On the Windows host run `tailscale up` and note the MagicDNS hostname,
   for example `your-pc.tailxxxx.ts.net`.
2. Inside WSL, append your laptop or phone public key to
   `~/.ssh/authorized_keys`.
3. Termius profile for WSL homelab: host is the MagicDNS name, port 2222,
   user is your WSL username, key authentication.
   Windows host SSH uses port 22.
4. Connect to the Windows host's tailnet IP or MagicDNS name on port 2222.
   Windows host SSH remains on port 22 for admin/reboot.

## Conventions

- Personal projects are not managed by this repo.
- Service data lives in `/srv/homelab/data/<service>`.
- Model weights live in `/srv/homelab/models/`.
- Backups live in `/srv/homelab/backups/`. The repo is
  reproducible from scripts; data is not. Back data up separately.
- Tmux is manual. The helper `tm <name>` in `bashrc.local` attaches to or
  creates a named session when you ask for one.

## Restoring on a new machine

1. Fresh Windows install. Clone this repo into `%UserProfile%\homelab`.
2. Run `scripts\windows\00-prereqs.ps1`. Reboot if asked, then re-run.
3. Run `scripts\windows\01-tailscale.ps1`, then `tailscale up`.
4. Install Ubuntu in WSL, finish the first-run setup, then run the WSL
   `make` steps above.
5. Restore `/srv/homelab/data` and `/srv/homelab/models` from your backup target.
6. Append authorized public keys to `~/.ssh/authorized_keys`.

## Gaming impact

WSL2 idle is cheap. The bundled `.wslconfig` caps memory at 16 GB and
processors at 12 to leave headroom for games. Stop GPU-heavy workloads
(Ollama, training jobs) before launching a game; the RTX 4060 Ti's 8 GB
VRAM is shared, and Windows plus the game plus a loaded model will OOM
the GPU. There is no software guard for this; it is a manual rule.

## Further reading

Long-form context lives in [`docs/`](docs/README.md):

- [`docs/architecture.md`](docs/architecture.md) -- layers and traffic flow
- [`docs/decisions.md`](docs/decisions.md) -- ADRs explaining the choices
- [`docs/networking.md`](docs/networking.md) -- WSL NAT, portproxy, and Tailscale wiring
- [`docs/gpu-and-llm.md`](docs/gpu-and-llm.md) -- VRAM budget and Ollama notes
- [`docs/operations.md`](docs/operations.md) -- runbook for common ops
- [`docs/management-cli.md`](docs/management-cli.md) -- `hl` terminal manager
- [`docs/troubleshooting.md`](docs/troubleshooting.md) -- symptom -> fix
- [`docs/inventory.md`](docs/inventory.md) -- living state snapshot

## License

Personal configuration. Reuse anything.
