# Operations runbook

## SSH in from a new device

1. On the new device, generate a key if you do not have one:
   `ssh-keygen -t ed25519 -C "<device-name>"`
2. Copy the public key (`.pub`) into `~/.ssh/authorized_keys` on this
   box. Either paste it via an existing session, or open Ubuntu from
   the Windows Start menu and paste from clipboard.
3. Verify perms inside WSL:
   `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`
4. From the new device on the tailnet:
   `ssh <wsl-user>@<magicdns-name>`
5. The `bashrc.local` auto-attach sends you straight into the `main`
   tmux session.

## Tmux quick reference

Prefix is `Ctrl-a`. The bashrc helper `tm <name>` attaches or creates a
session by name.

| Action | Keys |
| --- | --- |
| New window | `Ctrl-a c` |
| Vertical split | `Ctrl-a |` |
| Horizontal split | `Ctrl-a -` |
| Move between panes | `Ctrl-a h/j/k/l` |
| Detach | `Ctrl-a d` |
| Reload config | `Ctrl-a r` |
| Copy mode (vi keys) | `Ctrl-a [` then `v` to select, `y` to yank |

Convention: one tmux session per intent (`main`, `infra`,
`<project>`). Detach instead of kill so context is preserved.

## Updating things

```bash
# WSL kernel (run from Windows, not WSL)
wsl --update

# Ubuntu packages (inside WSL)
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get autoremove --purge -y

# Docker images (inside WSL)
docker compose -f docker/ollama/compose.yaml pull
make ollama-down && make ollama-up

# Tailscale (inside WSL only if installed there)
sudo tailscale update    # newer versions handle this automatically
```

## Restart things

```bash
# sshd (inside WSL)
sudo systemctl restart ssh

# docker (inside WSL)
sudo systemctl restart docker

# the whole WSL VM (run from Windows)
wsl --shutdown            # next command starts it again

# specific distro only (run from Windows)
wsl --terminate Ubuntu
```

## Reload config files

| File | After editing run |
| --- | --- |
| `%UserProfile%\.wslconfig` (Windows) | `wsl --shutdown` |
| `/etc/wsl.conf` (inside WSL) | `wsl --terminate <distro>` from Windows |
| `/etc/ssh/sshd_config` | `sudo systemctl restart ssh` |
| `~/.tmux.conf` | `Ctrl-a r` inside any tmux session |
| `~/.bashrc` / `~/.bashrc.local` | `exec bash` or open a new shell |

## Add a new compose service

1. Create `docker/<name>/compose.yaml`. Bind ports to `127.0.0.1`
   unless you have a reason not to.
2. Add a Makefile target if you will run it often:
   ```
   <name>-up:    docker compose -f docker/<name>/compose.yaml up -d
   <name>-down:  docker compose -f docker/<name>/compose.yaml down
   <name>-logs:  docker compose -f docker/<name>/compose.yaml logs -f
   ```
3. If the service writes to disk: bind to a named volume or to a path
   under `~/srv/data/<name>` (gitignored).
4. Commit the compose file. Do not commit `.env`; commit `.env.example`
   if there are required variables.

## Daily routine: gaming day

```bash
# Stop heavy GPU workloads
make ollama-down
# Optional, if you want WSL to give RAM back fully:
wsl --shutdown    # in a Windows shell
```

When done gaming, reattach:

```bash
make ollama-up    # if it was stopped
ssh <user>@<host> # auto-attaches to tmux 'main'
```

## Backups

The repo is reproducible. Data is not. Back up these from inside WSL:

| Path | Why |
| --- | --- |
| `~/srv/projects/` | working code that is not yet pushed |
| `~/srv/data/` | service databases, app state |
| `~/srv/models/` | optional; large but redownloadable |
| `~/.ssh/` | private keys, authorized_keys |
| `~/.gitconfig` | personal git config (not the template) |

Local snapshot recipe (good enough until we add restic / borg):

```bash
ts=$(date +%Y%m%d-%H%M%S)
tar --exclude='*/node_modules' --exclude='*/.venv' --exclude='*/__pycache__' \
    -czf "$HOME/srv/backups/projects-$ts.tar.gz" -C "$HOME/srv" projects

docker run --rm -v ollama-data:/data -v "$HOME/srv/backups:/backup" alpine \
    sh -c "tar -czf /backup/ollama-data-$ts.tar.gz -C /data ."
```

Off-site target later: pick one of restic to S3-compatible (Backblaze
B2, Cloudflare R2), borg to a remote box, or rsync to a NAS.

## Adding a project repo

```bash
mkdir -p ~/srv/projects
cd ~/srv/projects
git clone git@github.com:<you>/<project>.git
cd <project>
# do not nest projects inside this homelab repo
```

Project repos are independent. They show up under `~/srv/projects/`
and are never tracked by `homelab`.
