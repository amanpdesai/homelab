#!/usr/bin/env bash
# 00-bootstrap.sh -- runs inside WSL2 Ubuntu. Idempotent.
#
# Installs /etc/wsl.conf, base packages, sshd (key auth only), and the
# ~/srv layout. Re-run any time you bump packages or tweak wsl.conf.

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

# sshd: regenerate host keys, harden, enable
log "Configuring sshd"
if ! ls /etc/ssh/ssh_host_ed25519_key >/dev/null 2>&1; then
	sudo ssh-keygen -A
fi
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/'             /etc/ssh/sshd_config

if pidof systemd >/dev/null 2>&1; then
	sudo systemctl enable --now ssh
	ok "sshd enabled via systemd"
else
	warn "systemd not running yet -- run 'wsl --shutdown' from Windows, then re-run this script."
fi

# ~/srv layout
log "Creating ~/srv layout"
mkdir -p "$HOME/srv"/{projects,models,data,backups,logs}
ok "~/srv tree ready"

# SSH key for outbound auth
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
	log "Generating ed25519 SSH key"
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"
	ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" -C "$(whoami)@$(hostname)"
	ok "SSH key generated at ~/.ssh/id_ed25519"
fi

# authorized_keys placeholder
mkdir -p "$HOME/.ssh"
touch    "$HOME/.ssh/authorized_keys"
chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/authorized_keys"

ok "Bootstrap complete."
echo
echo "Next: make dotfiles"
echo "      make docker"
echo "      make tailscale-wsl   (only if mirrored networking cannot reach WSL)"
