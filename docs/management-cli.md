# Management CLI: `hl`

`hl` is the homelab terminal manager. One command, callable from any
shell on the box (also installed system-wide at `/usr/local/bin/hl` so
the MOTD can find it). All real interaction with the server -- looking
at status, starting and stopping services, managing the GPU, opening
the dashboard -- goes through `hl <subcommand>`. There is no web UI
and no daemon; `hl` is just a bash dispatcher around `docker`,
`nvidia-smi`, `tailscale`, `tmux`, `fzf`, `ncdu`, and `lazydocker`.

Windows-side lifecycle control is separate: from the repo root on the
Windows host, use `.\homelab.ps1 status`, `start`, `stop`, or `restart`
to manage the WSL instance itself.

## Install

Inside WSL, after `make bootstrap` and `make docker` have run:

```bash
make tui
```

This installs apt deps (`fzf`, `ncdu`, `lnav`, `bat`, `jq`,
`iproute2`), grabs `lazydocker` from upstream, symlinks `hl` into
`/usr/local/bin`, drops the homelab MOTD into `/etc/update-motd.d/`,
and disables the noisy default Ubuntu MOTD blocks. Re-run any time
you pull updates.

## Login experience

After `make tui`, every interactive SSH login prints a short
instance-style banner before the prompt:

```
================================================================================
  homelab   Ubuntu 24.04.1 LTS   up 4 days, 12 hours   Mon 27 Apr 2026 14:32 EDT
--------------------------------------------------------------------------------
  Load:        0.42, 0.51, 0.39
  Memory:      6.1 / 16.0 GB (38%)
  Disk /:      124 / 930 GB (13%)
  Disk /srv:   41 GB
  GPU:         NVIDIA GeForce RTX 4060 Ti, 5.8 / 8.0 GB VRAM (12%), 73 C
  Tailscale:   100.x.x.x  (homelab.tailxxxx.ts.net)
================================================================================
  Type 'hl' for the menu, or 'hl help' for a cheatsheet.

aman@homelab:~$
```

No tmux auto-attach. You get a regular shell. Run `tm <name>` (helper
in `bashrc.local`) when you want a persistent session, or `hl dash` for
the dashboard.

## Commands

### Status and info

| Command | What it does |
| --- | --- |
| `hl` | Interactive fzf menu of every subcommand |
| `hl status` | Full snapshot: host + GPU + tailnet + services |
| `hl status --motd` | The compact banner only (no services). Used by the MOTD. |
| `hl status --plain` | Same as above without ANSI colors. |
| `hl version` | Git rev of the homelab repo this `hl` runs from. |
| `hl help [topic]` | Cheatsheet. |

### Compose stacks (services)

Every directory under `docker/` containing a `compose.yaml` is a
"stack." `hl` discovers them automatically; no registration needed.

| Command | What it does |
| --- | --- |
| `hl ps` | List every stack and its containers, with status and ports. Also lists standalone containers. |
| `hl up [stack]` | `docker compose up -d`. Without a name, fzf-pick from discovered stacks. |
| `hl down [stack]` | `docker compose down`. |
| `hl restart [stack]` | Restart all containers in the stack. |
| `hl logs [stack\|container]` | Follow logs. Defaults to the last 200 lines, then tail. `-n N` to change. |
| `hl exec [container] [-- cmd]` | Drop into bash (then sh) inside a container, or run an explicit command. |

### GPU and Ollama

| Command | What it does |
| --- | --- |
| `hl gpu` | One-shot GPU snapshot: name, VRAM, util, temp, power, plus compute apps and Ollama loaded models. |
| `hl gpu --watch` | Refresh every 2 seconds. |
| `hl ollama` | List installed models and what is loaded into VRAM. |
| `hl ollama list` | Just the installed list. |
| `hl ollama pull <model>` | Pull a model from the Ollama registry. |
| `hl ollama run <model>` | Interactive chat (drops into the container). |
| `hl ollama pick` | fzf-pick an installed model and run it. |
| `hl ollama evict` | Stop every loaded model so VRAM is freed. |
| `hl ollama rm <model>` | Delete a model (asks first). |
| `hl game-on` | Stop every GPU-tagged stack. Use before launching a game. |
| `hl game-off` | Bring those stacks back up. |

A stack is "GPU" if its compose file has `driver: nvidia` in a device
reservation, or if it carries `x-homelab-gpu: true` at the top level.
Add either to mark a stack so `hl game-on` knows to stop it.

### Operations

| Command | What it does |
| --- | --- |
| `hl net` | Tailnet status, listening ports, and connectivity checks (1.1.1.1, github.com, derp). |
| `hl disk` | `df`, biggest top-level dirs in `/srv/homelab`, `docker system df`. `--ncdu` opens ncdu in `/srv/homelab` for interactive browsing. |
| `hl dash` | Build (or attach to) the `home` tmux session: a four-pane monitor (btop, GPU watch, docker watch, tailnet watch), plus a free shell window and a lazydocker window. |
| `hl doctor` | Readiness checks for WSL, systemd, sshd, Docker, GPU, Tailscale, compose stacks, disk, repo path, and SSH key permissions. |
| `hl keys list` | List inbound WSL SSH public keys with labels and fingerprints. |
| `hl keys add <name> <public-key>` | Add a public key to `~/.ssh/authorized_keys` with a stable `homelab:<name>` label. |
| `hl keys remove <name\|fingerprint>` | Remove authorized keys by label or fingerprint. |
| `hl update [--prune]` | Update Ubuntu packages, pull compose images, recreate stacks, and optionally prune unused Docker data. |

## The `hl dash` dashboard

```
+------------------------------------+--------------------------------+
|                                    |  GPU watch                     |
|        btop                        |  nvidia-smi every 2 s          |
|     (CPU + RAM + IO)               +--------------------------------+
|                                    |  Containers                    |
|                                    |  docker ps every 5 s           |
|                                    +--------------------------------+
|                                    |  Network                       |
|                                    |  tailscale status every 10 s   |
+------------------------------------+--------------------------------+
```

Mouse mode is on (already configured in `dotfiles/tmux.conf`):

- Tap a pane in Termius to focus it.
- `Ctrl-a z` zooms a pane to fullscreen; another `Ctrl-a z` un-zooms.
- `Ctrl-a d` detaches; reattach later with `hl dash` or `tmux attach -t home`.
- The status bar shows windows. Tap a window number to jump to it.

Three windows in the `home` session:

- `monitor`: the four-pane dashboard above
- `shell`: a free shell that runs `hl status` on entry; type any
  `hl ...` command here to act on what the dashboard is showing.
- `docker`: full-screen `lazydocker` (only if it is installed).

`hl dash` is idempotent: if `home` already exists it just attaches.
SSH login itself never auto-attaches tmux; `hl dash` is an explicit command.

## Conventions inside `hl`

- All subcommands live as sibling files: `hl-<sub>` next to `hl`.
- All sources include `lib.sh` for color, header, table, fzf, confirm,
  stack-discovery, and environment-probe helpers.
- Output is plain ANSI by default; `--plain` (where supported) and
  `NO_COLOR=1` strip colors.
- Status tags are ASCII -- `[ok]`, `[warn]`, `[err]`, `[off]` -- not
  emojis or unicode glyphs.
- Destructive operations (`hl ollama rm`, future `hl prune`) confirm
  before acting unless stdin is non-TTY.
- Every subcommand accepts `-h` / `--help`.

## Adding a new subcommand

1. Create `scripts/wsl/hl/hl-<name>` (executable, LF endings) that
   sources `lib.sh` from its sibling directory.
2. Add a row to the menu list in `scripts/wsl/hl/hl` if you want it to
   appear in the bare `hl` menu.
3. Add a row to this file and to `hl-help` so the cheatsheet stays current.
4. Commit. `hl` discovers the new file the next time it dispatches.

## Adding a new compose stack

1. Create `docker/<name>/compose.yaml`. Bind ports to `127.0.0.1`
   unless you have a reason not to. Add `restart: unless-stopped` so
   `hl game-off` actually brings it back after a Windows reboot.
2. If the stack uses the GPU, add a `driver: nvidia` device
   reservation, or `x-homelab-gpu: true` at the top level.
3. Done. `hl ps`, `hl up <name>`, `hl logs <name>`, etc. all work
   without further config.

## Future subcommands (planned)

- `hl sys` -- systemctl unit list; restart sshd / docker / tailscaled.
- `hl backup` -- run / list / restore via restic (or borg).
- `hl tree [path]` -- pretty `tree` of `/srv/homelab` or another path.
- `hl info` -- inventory snapshot mirroring docs/inventory.md.
- bash completion for `hl <tab>` and `hl up <tab>`.

These will land as additional `hl-*` files in subsequent commits.
