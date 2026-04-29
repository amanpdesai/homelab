# Decisions

Short ADR-style entries. Each captures the choice, the alternatives we
weighed, and the tradeoff we accepted. Add new entries at the bottom;
do not silently rewrite old ones (mark superseded if the decision flips).

---

## ADR-001: WSL2 over a dual-boot Linux install

**Choice:** Run Linux as a WSL2 guest under Windows, not a separate
boot partition.

**Alternatives:**
- Dual boot Ubuntu / Windows.
- Bare metal Ubuntu with Windows in a Hyper-V VM for games.
- A Hyper-V Linux VM alongside Windows (no WSL).

**Tradeoff accepted:**
- `+` One boot. Single GPU driver chain. Shared filesystem access from
   both sides. No GRUB/EFI churn.
- `+` Windows Tailscale plus explicit forwarding keeps Linux services
   private while still reachable from trusted tailnet devices.
- `+` Lower RAM and CPU floor than a fully partitioned VM.
- `-` Hyper-V flips an anti-cheat compatibility risk on for some games
   (Vanguard family). Acceptable for our game library.
- `-` GPU is shared, not partitioned. Manual discipline required to
   stop GPU workloads before launching a game.

---

## ADR-002: Native Docker Engine inside WSL over Docker Desktop

**Choice:** Install `docker-ce` directly in the Ubuntu distro and run
it under systemd.

**Alternatives:**
- Docker Desktop with WSL integration.
- Podman.

**Tradeoff accepted:**
- `+` No tray app, no auto-update surface, no licensing question.
- `+` Server-style operation: `systemctl status docker` is the truth.
- `+` Installs the NVIDIA Container Toolkit cleanly without working
   around Docker Desktop's GPU plumbing.
- `-` We lose the Docker Desktop GUI and its built-in Kubernetes.
   Acceptable; we are not running k8s here.
- `-` We are responsible for our own auto-start and updates. Trivial
   under systemd plus apt.

---

## ADR-003: Tailscale over public port forwarding or self-hosted VPN

**Choice:** Tailscale on the Windows host as the primary remote access
path. Devices that need in get on the tailnet; nothing is exposed to
the public internet.

**Alternatives:**
- Forward 22 / 11434 from the home router.
- Self-host a Wireguard server.
- Cloudflare Tunnel for HTTP services.

**Tradeoff accepted:**
- `+` No router config, no DDNS, no dynamic IP problems.
- `+` MagicDNS hostnames make Termius profiles trivial.
- `+` ACLs are real. Adding a friend or revoking a phone is one click.
- `-` We rely on Tailscale's coordination server. Acceptable for
   personal use; data plane is still peer to peer.
- `-` If we ever need *public* access (a website friends can hit
   without a tailnet account), we will need Tailscale Funnel or
   Cloudflare Tunnel layered on top.

---

## ADR-004: Default NAT plus portproxy over mirrored networking

**Choice:** Use WSL2 default NAT networking and refresh a Windows
`netsh interface portproxy` rule for WSL SSH from `homelab.ps1 start`.

**Alternatives:**
- `networkingMode=mirrored` in `.wslconfig`.
- Run Tailscale inside WSL too (still possible as a fallback).

**Tradeoff accepted:**
- `+` Works on the current host without depending on mirrored networking
   behavior.
- `+` Windows SSH stays on port 22 for admin/reboot; WSL SSH is cleanly
   separated on port 2222.
- `+` The helper script owns the moving WSL IP problem.
- `-` Portproxy must be refreshed after WSL gets a new IP. `start` and
   `restart` handle this when run as Administrator.
- `-` Each additional externally reachable WSL service needs its own
   deliberate forwarding rule.

---

## ADR-005: SSH key authentication only

**Choice:** `PasswordAuthentication no`, `PermitRootLogin no`,
`PubkeyAuthentication yes` in sshd_config, applied by the bootstrap
script.

**Alternatives:**
- Password plus key.
- TOTP / 2FA on top.

**Tradeoff accepted:**
- `+` No brute force surface. Lockout is one fewer thing to configure.
- `+` Termius and the macOS keychain handle keys cleanly.
- `-` If the only key is lost, recovery requires opening Ubuntu from
   the Windows Start menu and pasting a fresh public key. Acceptable
   on a single-host setup.

---

## ADR-006: Localhost-bound service ports, exposed only via Tailscale

**Choice:** Compose services bind to `127.0.0.1:<port>` on the WSL host
side. Tailscale handles remote access for trusted clients only.

**Alternatives:**
- Bind to `0.0.0.0` and rely on the Windows firewall.
- Per-service auth (basic auth, oauth proxy) and 0.0.0.0 binding.

**Tradeoff accepted:**
- `+` Smallest possible blast radius. A misconfigured Tailscale ACL
   does not expose the service to the local LAN.
- `-` Cross-device LAN access (a Chromecast trying to reach Jellyfin)
   would need an explicit binding change later.

---

## ADR-007: Config repo only, never a data repo

**Choice:** `homelab` tracks scripts and configs. Model weights, service
data, and project source code stay outside.

**Alternatives:**
- Single mono-repo with weights via Git LFS.
- Separate `homelab-data` repo with submodules.

**Tradeoff accepted:**
- `+` `git clone` is fast and small. Reset to a known good config is
   one `git reset --hard origin/main` away.
- `+` No accidental commit of large weights or secrets.
- `-` Backup of `/srv/homelab/data` and `/srv/homelab/models` must be solved
   separately (see operations.md).
