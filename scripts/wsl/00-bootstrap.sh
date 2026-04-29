#!/usr/bin/env bash
# 00-bootstrap.sh -- runs inside WSL2 Ubuntu. Idempotent.
#
# Installs /etc/wsl.conf, base packages, sshd (key auth only), and VM-level
# service directories. Re-run any time you bump packages or tweak wsl.conf.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

require_wsl
require_not_root
sudo -v || die "sudo failed"

# /etc/wsl.conf
log "Installing /etc/wsl.conf"
sudo install -m 0644 "$REPO_ROOT/wsl/wsl.conf" /etc/wsl.conf
ok "wsl.conf installed (run 'wsl --shutdown' from Windows once for systemd to take effect)"

# Base packages
log "Updating apt and installing base packages"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
	build-essential curl wget git vim tmux htop btop tree jq unzip zip make \
	ca-certificates gnupg lsb-release software-properties-common \
	openssh-server net-tools dnsutils iputils-ping ripgrep fd-find \
	python3 python3-pip python3-venv pipx \
	rsync less man-db locales tzdata
ok "Base packages installed"

# Snap creates ~/snap and extra mounts in WSL. This homelab image uses apt,
# pipx, and direct installers instead, so keep Snap out of the base VM.
if dpkg-query -W -f='${Status}' snapd 2>/dev/null | grep -q 'install ok installed'; then
	log "Removing Snap from WSL image"
	sudo snap remove --purge rustup >/dev/null 2>&1 || true
	sudo snap remove --purge core24 >/dev/null 2>&1 || true
	sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y snapd
	sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
	rm -rf "$HOME/snap"
	sudo rm -rf /snap /var/snap /var/lib/snapd
	ok "Snap removed"
fi

# sshd: regenerate host keys, harden, enable
log "Configuring sshd"
if ! ls /etc/ssh/ssh_host_ed25519_key >/dev/null 2>&1; then
	sudo ssh-keygen -A
fi
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/'             /etc/ssh/sshd_config
sudo install -d -m 0755 /etc/ssh/sshd_config.d
printf '%s\n' 'Port 2222' | sudo tee /etc/ssh/sshd_config.d/10-homelab-port.conf >/dev/null
cat <<'EOF' | sudo tee /etc/ssh/sshd_config.d/20-homelab-compat.conf >/dev/null
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,diffie-hellman-group14-sha256
HostKeyAlgorithms ssh-ed25519,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256
EOF

if pidof systemd >/dev/null 2>&1; then
	sudo systemctl disable --now ssh.socket >/dev/null 2>&1 || true
	sudo systemctl enable --now ssh
	ok "sshd enabled via systemd on port 2222"
else
	warn "systemd not running yet -- run 'wsl --shutdown' from Windows, then re-run this script."
fi

# WSL exposes the Windows GPU shim at /usr/lib/wsl/lib. Some SSH sessions
# can miss that directory in PATH, so publish nvidia-smi in a standard bin.
if [ -x /usr/lib/wsl/lib/nvidia-smi ]; then
	log "Configuring WSL GPU command path"
	sudo ln -sfn /usr/lib/wsl/lib/nvidia-smi /usr/local/bin/nvidia-smi
	ok "nvidia-smi available via /usr/local/bin"
fi

# VM-level service layout. Personal projects intentionally stay wherever the
# user wants them; this repo does not own a project workspace.
log "Creating /srv/homelab layout"
sudo install -d -m 0755 -o "$USER" -g "$USER" /srv/homelab
for d in data models backups logs; do
	sudo install -d -m 0755 -o "$USER" -g "$USER" "/srv/homelab/$d"
done
ok "/srv/homelab tree ready"

# authorized_keys placeholder
mkdir -p "$HOME/.ssh"
touch    "$HOME/.ssh/authorized_keys"
chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/authorized_keys"

ok "Bootstrap complete."
echo
echo "Next: make dotfiles"
echo "      make docker"
echo "      make tui"
echo "      make tailscale-wsl   (optional: make WSL its own tailnet node)"
