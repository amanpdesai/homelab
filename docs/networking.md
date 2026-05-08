# Networking

## Default WSL networking

By default WSL2 puts the guest behind a NAT on a private 172.x subnet.
The Windows host can reach the guest, but inbound connections from
*outside* the host (LAN, tailnet, anywhere) require port forwarding
rules with `netsh interface portproxy`. The forwarded port also has to
be opened in the Windows firewall, and the guest IP changes on each
boot, so the rules need to be regenerated.

This repo uses that default NAT mode. `.\homelab.ps1 start` starts the
distro and, when run as Administrator, refreshes:

```text
0.0.0.0:2222 on Windows -> <current WSL IPv4>:2222
```

`start` keeps the distro resident with a non-interactive Windows scheduled
task. The deployed `.wslconfig` also disables the WSL VM idle timeout, and the
systemd `homelab-keepalive` service inside WSL gives the Linux side a clear
health signal without opening a Windows terminal.

## Optional mirrored networking

Set in `wsl/wslconfig.example`:

```
networkingMode=mirrored
firewall=true
dnsTunneling=true
autoProxy=true
```

What it does:

- The WSL guest shares the Windows network stack instead of NATing.
  A service bound to `127.0.0.1:11434` *inside* WSL is reachable on
  the Windows host's `127.0.0.1:11434` *directly*.
- The Windows firewall now sees WSL traffic as a Hyper-V vNIC, so
  Windows firewall rules apply uniformly to both sides.
- DNS tunneling sends DNS queries through the Windows resolver, so
  corp DNS, split-horizon, and VPN DNS all behave like on Windows.
- AutoProxy picks up Windows proxy settings (HTTP_PROXY etc) inside
  the guest automatically.

Requirements:
- Windows 11 22H2 or later.
- After editing `.wslconfig`, run `wsl --shutdown` so it is reread.

## Tailscale wiring

Primary path: Tailscale runs on the Windows host. Tailnet peers connect
to Windows port 2222, and Windows forwards that to WSL sshd with
`netsh interface portproxy`.

Fallback path: install Tailscale inside the WSL distro
(`make tailscale-wsl`) so the distro joins the tailnet as its own
node. Use this when mirrored networking misbehaves (rare, but seen on
some Windows builds and certain enterprise networks).

```
                 default mode (chosen)     mirrored mode (optional)
phone -----------> tailscaled (Windows) ---> tailscaled (Windows)
                       |                          |
                   portproxy rule                 |  shared
                   per service                    |  loopback
                       v                          v
                   netsh -> WSL guest         WSL service on 127.0.0.1
```

## Verifying it works

From Windows:

```powershell
tailscale status                # confirm we have a tailnet IP
tailscale netcheck              # NAT type, derp latency
Test-NetConnection 127.0.0.1 -Port 22
Test-NetConnection 127.0.0.1 -Port 2222
```

From WSL:

```bash
ss -tlnp                        # what is listening, on which interfaces
ip -br addr                     # IPs the guest sees (mirrored = host IPs)
ping 1.1.1.1                    # outbound
getent hosts github.com         # DNS via tunneling
```

From another tailnet device:

```bash
tailscale ping <magicdns-name>
ssh -v <windows-user>@<magicdns-name>
ssh -v -p 2222 <wsl-user>@<magicdns-name>
```

## Common port assignments

| Port | Service | Bound to | Exposed to |
| ---- | ------- | -------- | ---------- |
| 22    | Windows sshd | 0.0.0.0 on Windows      | tailnet only (Windows firewall + Tailscale ACL) |
| 2222  | WSL sshd     | 0.0.0.0 inside WSL      | tailnet via Windows portproxy |
| 11434 | ollama     | 127.0.0.1 inside WSL    | tailnet only via Windows host loopback |
| 3000+ | dev servers (vite, next, etc) | 127.0.0.1 inside WSL | tailnet, ad-hoc |

If a service needs to be reachable from the local LAN (not just the
tailnet), bind it to `0.0.0.0` *and* add a Windows firewall rule. Do
not bind to `0.0.0.0` casually; mirrored networking makes that the
real public-on-LAN binding.

## Debugging recipes

### "I cannot ssh from my phone"

1. On Windows: `tailscale status` -- is the host online and listed as
   `100.x.x.x`? If not, `tailscale up` and authenticate.
2. On Windows: run `.\homelab.ps1 start` from Administrator PowerShell,
   then `Test-NetConnection 127.0.0.1 -Port 2222`. If false, WSL sshd is
   not running. Open Ubuntu and `sudo systemctl status ssh`.
3. On phone tailnet device: `tailscale ping <host>`. If high latency
   or relayed via DERP, that is fine -- it should still connect.
4. From phone Termius: ensure key is loaded; ensure the host name uses
   the MagicDNS short name, not a 100.x IP, so ACLs match. Use port 2222
   for WSL homelab SSH; port 22 is the Windows host SSH admin shell.

### "Mirrored networking does not seem to work"

1. Confirm Win11 build: `winver` -- needs 22H2 or later.
2. `wsl --shutdown` then re-enter. The mode applies on next boot only.
3. Check `wsl --status` for the active networking mode.
4. If broken: remove or comment `networkingMode=mirrored`, run
   `wsl --shutdown`, then use the default NAT plus portproxy path.
