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
   `ssh -p 2222 <wsl-user>@<magicdns-name>`
5. The login banner prints a compact `hl status --motd` snapshot. Run
   `tm main` if you want a persistent tmux session.

Inside WSL, use `hl keys` for future key changes:

```bash
hl keys list
hl keys add macbook "ssh-ed25519 AAAA... user@example.com"
hl keys remove macbook
```

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

Convention: name tmux sessions by what you are doing (`main`, `infra`,
or any name you choose). Detach instead of kill so context is preserved.

## Updating things

```bash
# WSL kernel plus in-distro updates (run from Windows)
.\homelab.ps1 update

# Ubuntu packages plus Docker compose images (inside WSL)
hl update

# Health/readiness checks after updates
hl doctor

# Tailscale (inside WSL only if installed there)
sudo tailscale update    # newer versions handle this automatically
```

## Restart things

From Windows:

```powershell
# current state without opening an interactive shell
.\homelab.ps1 status

# start/stop/restart the WSL homelab distro
.\homelab.ps1 start
.\homelab.ps1 stop
.\homelab.ps1 restart

# open a normal WSL shell, or SSH through localhost
.\homelab.ps1 shell
.\homelab.ps1 ssh -User <wsl-user>
```

Under the hood this auto-selects `Ubuntu-24.04`, `Ubuntu`, or the first
non-Docker WSL distro, then uses `wsl -d <distro>` to start it and
`wsl --terminate <distro>` to stop it. It does not auto-attach tmux.

```bash
# sshd (inside WSL)
sudo systemctl restart ssh

# docker (inside WSL)
sudo systemctl restart docker

# the whole WSL VM (run from Windows)
wsl --shutdown            # next command starts it again

# specific distro only (run from Windows, if bypassing instance.ps1)
wsl --terminate <distro>
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
   under `/srv/homelab/data/<name>`.
4. Commit the compose file. Do not commit `.env`; commit `.env.example`
   if there are required variables.

## Daily routine: gaming day

```bash
# Stop heavy GPU workloads
hl game-on
# Optional, if you want WSL to give RAM back fully:
wsl --shutdown    # in a Windows shell
```

When done gaming, reattach:

```bash
ssh <user>@<host>
hl game-off       # if GPU stacks were stopped
tm main           # optional persistent shell
```

## Backups

The repo is reproducible. Data is not. Back up these from inside WSL:

| Path | Why |
| --- | --- |
| your project dirs | working code that is not yet pushed |
| `/srv/homelab/data/` | service databases, app state |
| `/srv/homelab/models/` | optional; large but redownloadable |
| `~/.ssh/` | private keys, authorized_keys |
| `~/.gitconfig` | personal git config (not the template) |

Local snapshot recipe (good enough until we add restic / borg):

```bash
ts=$(date +%Y%m%d-%H%M%S)
tar --exclude='*/node_modules' --exclude='*/.venv' --exclude='*/__pycache__' \
    -czf "/srv/homelab/backups/home-projects-$ts.tar.gz" -C "$HOME" .

docker run --rm -v ollama-data:/data -v "/srv/homelab/backups:/backup" alpine \
    sh -c "tar -czf /backup/ollama-data-$ts.tar.gz -C /data ."
```

Off-site target later: pick one of restic to S3-compatible (Backblaze
B2, Cloudflare R2), borg to a remote box, or rsync to a NAS.

## Adding a project repo

Project repos are not managed by homelab. Put them wherever you normally
work, for example directly under your home directory:

```bash
cd ~
git clone git@github.com:<you>/<project>.git
```

Do not nest personal projects inside `/opt/homelab`; that path is only for
the VM control repo.
