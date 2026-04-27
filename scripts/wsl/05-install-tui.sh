#!/usr/bin/env bash
# 05-install-tui.sh -- install hl (homelab terminal manager) and its deps.
# Idempotent. Re-run any time after pulling new hl scripts.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/../lib.sh"

require_wsl
require_not_root
sudo -v || die "sudo failed"

# 1. apt deps
log "Installing TUI dependencies (fzf, ncdu, lnav, bat, jq, iproute2)"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
	fzf ncdu lnav bat jq iproute2

# Ubuntu installs `bat` as `batcat`; symlink for convenience.
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
	mkdir -p "$HOME/.local/bin"
	ln -sfn "$(command -v batcat)" "$HOME/.local/bin/bat"
fi
ok "apt deps installed"

# 2. lazydocker (no apt package; grab the latest release)
if ! command -v lazydocker >/dev/null 2>&1; then
	log "Installing lazydocker"
	tmpdir=$(mktemp -d)
	pushd "$tmpdir" >/dev/null
	# install_update_linux.sh writes to ~/.local/bin/lazydocker
	curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
	popd >/dev/null
	rm -rf "$tmpdir"
	if [ -x "$HOME/.local/bin/lazydocker" ]; then
		sudo install -m 0755 "$HOME/.local/bin/lazydocker" /usr/local/bin/lazydocker
		ok "lazydocker installed system-wide"
	else
		warn "lazydocker installer did not produce ~/.local/bin/lazydocker; skipping system-wide install"
	fi
fi

# 3. mark all hl scripts executable (in case git lost the bit)
log "Setting executable bits on hl scripts"
chmod +x "$REPO_ROOT/scripts/wsl/hl/"hl* "$REPO_ROOT/scripts/wsl/hl/motd-homelab.sh"

# 4. symlink hl into /usr/local/bin (system-wide so MOTD scripts find it)
log "Installing hl into /usr/local/bin/hl"
sudo ln -sfn "$REPO_ROOT/scripts/wsl/hl/hl" /usr/local/bin/hl
ok "hl installed: $(/usr/local/bin/hl --version 2>/dev/null || echo no-git-info)"

# 5. MOTD: drop our script, neutralize the noisy defaults
log "Configuring MOTD"
sudo install -m 0755 "$REPO_ROOT/scripts/wsl/hl/motd-homelab.sh" /etc/update-motd.d/50-homelab

# Disable chatty default MOTD scripts (safe to leave alone if absent).
for f in \
	/etc/update-motd.d/10-help-text \
	/etc/update-motd.d/50-motd-news \
	/etc/update-motd.d/85-fwupd \
	/etc/update-motd.d/88-esm-announce \
	/etc/update-motd.d/90-updates-available \
	/etc/update-motd.d/91-contract-ua-esm-status \
	/etc/update-motd.d/91-release-upgrade \
	/etc/update-motd.d/95-hwe-eol \
	/etc/update-motd.d/98-fsck-at-reboot \
	/etc/update-motd.d/98-reboot-required
do
	[ -e "$f" ] && sudo chmod -x "$f" || true
done

# Suppress legacy /etc/motd content; pam_motd will only emit our update-motd.d output.
sudo truncate -s 0 /etc/motd 2>/dev/null || true

# Suppress the "Last login" line without using ~/.hushlogin. A hushlogin
# file can suppress pam_motd too, which would hide the homelab banner.
if [ -f "$HOME/.hushlogin" ]; then
	mv "$HOME/.hushlogin" "$HOME/.hushlogin.disabled-by-homelab"
	warn "Moved ~/.hushlogin aside so the homelab MOTD can render"
fi
sudo install -d -m 0755 /etc/ssh/sshd_config.d
printf '%s\n' 'PrintLastLog no' | sudo tee /etc/ssh/sshd_config.d/99-homelab-motd.conf >/dev/null
if pidof systemd >/dev/null 2>&1; then
	sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd 2>/dev/null || true
fi
ok "MOTD configured (50-homelab is the only active block)"

echo
ok "hl is ready. Try:  hl status   |   hl   |   hl help"
