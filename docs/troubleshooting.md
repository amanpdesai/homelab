# Troubleshooting

Symptom -> diagnosis -> fix. Add new entries as we hit them.

---

## "WSL2 is not supported with your current machine configuration"

`wsl --status` shows the message even when WSL works.

- Confirm virtualization is on in BIOS. Task Manager -> Performance ->
  CPU -> "Virtualization: Enabled".
- Confirm the optional features:
  ```powershell
  Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
  Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
  ```
  Both should be "Enabled". If not:
  ```powershell
  Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart
  ```
  Reboot afterwards.
- Run `wsl --update`. The newer Microsoft Store-shipped WSL fixes most
  weird `wsl --status` complaints.

---

## "Permission denied (publickey)" when SSH-ing in

The bootstrap disables password auth, so this is the only failure mode
you should ever see for inbound SSH.

1. On the host, inside WSL:
   ```bash
   ls -la ~/.ssh
   # ~/.ssh must be 700, ~/.ssh/authorized_keys must be 600
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ```
2. Confirm the public key actually made it in:
   ```bash
   cat ~/.ssh/authorized_keys
   ```
3. Confirm sshd config is right:
   ```bash
   sudo grep -E '^(PasswordAuthentication|PubkeyAuthentication|PermitRootLogin)' /etc/ssh/sshd_config
   sudo systemctl restart ssh
   ```
4. From the client, run with `-v` -- it tells you whether the right
   key is being offered.

---

## SSH from outside the host hangs / times out

- `tailscale status` on the Windows host. Is the host listed and up?
  If not, `tailscale up`.
- On the client: `tailscale ping <magicdns>`. If this fails, the
  problem is the tailnet, not WSL.
- On the host (Windows shell): `Test-NetConnection 127.0.0.1 -Port 22`.
  If false, sshd is not running. Start WSL and run
  `sudo systemctl status ssh`.
- If mirrored networking is off and the default NAT is in effect,
  install Tailscale inside WSL (`make tailscale-wsl`) so the WSL distro
  joins the tailnet directly.

---

## `nvidia-smi` works in WSL but not in a Docker container

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
# Error: could not select device driver "" with capabilities: [[gpu]]
```

The NVIDIA Container Toolkit is not wired into Docker. Fix:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

If `nvidia-ctk` is missing, re-run `make docker`.

---

## WSL is using too much RAM

WSL2 holds memory until idle. The `.wslconfig` here enables
`autoMemoryReclaim=gradual`, but reclamation is slow.

Force release:

```powershell
wsl --shutdown
```

Permanent: lower `memory=` in `.wslconfig` (currently 16 GB) and
`wsl --shutdown` to apply.

If the issue is *runaway* memory, find the culprit inside WSL:

```bash
ps aux --sort=-rss | head
```

Common culprits: a stuck Node dev server with a leak, a Python REPL
with a giant dataframe, Docker containers with no memory limit.

---

## systemd commands fail with "Failed to connect to bus"

`/etc/wsl.conf` does not have `systemd=true`, or the distro has not
been restarted since the change.

```bash
sudo install -m 0644 ~/srv/homelab/wsl/wsl.conf /etc/wsl.conf
exit
# from Windows:
wsl --shutdown
# re-enter WSL, then verify:
pidof systemd
```

---

## `docker compose` reports permission denied on the socket

You were just added to the `docker` group but your shell does not see
it yet.

```bash
newgrp docker      # current shell only, takes effect immediately
# or just open a fresh shell / re-ssh
```

---

## Ollama is slow / clearly running on CPU

Inside the container:

```bash
docker compose -f docker/ollama/compose.yaml exec ollama nvidia-smi
```

If `nvidia-smi` is missing or the running model does not appear in the
process list there, GPU passthrough is broken. See the toolkit fix
above.

If GPU is fine but the model is still slow: it may be larger than
VRAM and Ollama is offloading layers to CPU. Use `ollama ps` to
confirm split, and pick a smaller quantization.

---

## CRLF line endings break a shell script

Symptom: `bash: ./script.sh: /usr/bin/env: bad interpreter`.

The repo's `.gitattributes` pins `*.sh` to LF, but a file edited on
Windows by a tool that does not respect gitattributes can still slip
through.

```bash
file scripts/wsl/00-bootstrap.sh
# expect "ASCII text" not "ASCII text, with CRLF line terminators"

# Fix in place:
sed -i 's/\r$//' scripts/wsl/00-bootstrap.sh
```

---

## `wsl --shutdown` did not pick up new `.wslconfig`

There is a known race where the WSL service stays alive briefly after
`wsl --shutdown`. Quick fix:

```powershell
wsl --shutdown
Start-Sleep -Seconds 8     # let the VM actually exit
wsl                         # this triggers a cold start with new config
```

---

## Docker Desktop and native Docker conflict

Both manage `/var/run/docker.sock` from inside their own world; with
both installed you get unpredictable behavior.

Fix: pick one. We use native. Uninstall Docker Desktop from Windows
("Apps & features" -> Docker Desktop -> Uninstall), then unregister
its WSL helpers if they linger:

```powershell
wsl -l -v
wsl --unregister docker-desktop
wsl --unregister docker-desktop-data    # if present
```

This is destructive only to the Docker Desktop helper distros; user
data lives in named volumes that the *native* docker engine will
not see anyway, so nothing of yours is lost by removing them.
