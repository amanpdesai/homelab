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
    |-- tmux                    persistent sessions per project
    |-- docker engine           native; GPU passthrough via NVIDIA toolkit
    +-- ~/srv/                  projects, models, data, backups
```

Key choices:

- WSL2 with mirrored networking so the Windows host shares a network stack
  with the guest and Tailscale on Windows can reach WSL2 ports directly.
- Native Docker Engine inside WSL2, not Docker Desktop.
- Tailscale on the Windows host as the primary path. Tailscale inside WSL is
  optional and only needed if mirrored networking does not behave on a given
  Windows build.
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

## Host filesystem layout

Everything inside WSL lives under `~/srv`:

```
~/srv/
|-- homelab/        this repo
|-- projects/       work and personal projects, each its own git repo
|-- models/         LLM weights and similar large blobs (gitignored)
|-- data/           service data volumes (gitignored)
|-- backups/        local snapshots (gitignored)
+-- logs/
```

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

### 2. Inside WSL2 Ubuntu

```bash
sudo apt-get update && sudo apt-get install -y git make
git clone https://github.com/amanpdesai/homelab.git ~/srv/homelab
cd ~/srv/homelab

make bootstrap       # base packages, sshd, ~/srv layout
make dotfiles        # symlink tmux, bash, git, inputrc, ssh config
make docker          # docker engine plus NVIDIA container toolkit
make tui             # install hl terminal manager and compact login MOTD
hl doctor            # verify readiness
# Optional, only if mirrored networking cannot reach WSL services:
# make tailscale-wsl
```

After `make bootstrap`, run `wsl --shutdown` from a Windows shell once so
that `/etc/wsl.conf`'s `systemd=true` takes effect.

## Remote access via Termius

1. On the Windows host run `tailscale up` and note the MagicDNS hostname,
   for example `your-pc.tailxxxx.ts.net`.
2. Inside WSL, append your laptop or phone public key to
   `~/.ssh/authorized_keys`.
3. Termius profile: host is the MagicDNS name, port 22, user is your WSL
   username, key authentication.
4. With mirrored networking, the Windows host's port 22 forwards to the
   WSL sshd. If that fails on your Windows build, run `make tailscale-wsl`
   inside WSL and connect to the WSL Tailscale node directly.

## Conventions

- Project repos live in `~/srv/projects/<name>`. They are separate git repos
  and never tracked by this one.
- Service data lives in `~/srv/data/<service>` and is gitignored.
- Model weights live in `~/srv/models/` and are gitignored.
- Backups live in `~/srv/backups/` and are gitignored. The repo is
  reproducible from scripts; data is not. Back data up separately.
- Tmux sessions are named by intent (`main`, `infra`, `<project>`). The
  helper `tm <name>` in `bashrc.local` attaches to or creates the session.

## Restoring on a new machine

1. Fresh Windows install. Clone this repo into `%UserProfile%\homelab`.
2. Run `scripts\windows\00-prereqs.ps1`. Reboot if asked, then re-run.
3. Run `scripts\windows\01-tailscale.ps1`, then `tailscale up`.
4. Install Ubuntu in WSL, finish the first-run setup, then run the WSL
   `make` steps above.
5. Restore `~/srv/data` and `~/srv/models` from your backup target.
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
- [`docs/networking.md`](docs/networking.md) -- mirrored networking and Tailscale wiring
- [`docs/gpu-and-llm.md`](docs/gpu-and-llm.md) -- VRAM budget and Ollama notes
- [`docs/operations.md`](docs/operations.md) -- runbook for common ops
- [`docs/management-cli.md`](docs/management-cli.md) -- `hl` terminal manager
- [`docs/troubleshooting.md`](docs/troubleshooting.md) -- symptom -> fix
- [`docs/inventory.md`](docs/inventory.md) -- living state snapshot

## License

Personal configuration. Reuse anything.
