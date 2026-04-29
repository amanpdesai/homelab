#!/usr/bin/env bash
# 03-tailscale.sh -- install Tailscale inside WSL.
#
# Optional. The default path is Tailscale on Windows plus explicit
# Windows portproxy rules into WSL. Install Tailscale inside WSL only
# when you want the distro to appear as its own tailnet node.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

require_wsl
require_not_root
sudo -v || die "sudo failed"

if command -v tailscale >/dev/null 2>&1; then
	ok "tailscale already installed: $(tailscale version | head -1)"
else
	log "Installing Tailscale"
	curl -fsSL https://tailscale.com/install.sh | sh
fi

if pidof systemd >/dev/null 2>&1; then
	sudo systemctl enable --now tailscaled
	ok "tailscaled enabled via systemd"
else
	warn "systemd not running -- start tailscaled manually after 'wsl --shutdown' from Windows."
fi

echo
echo "Bring up the tunnel:"
echo "  sudo tailscale up --ssh --hostname=homelab-wsl"
echo
echo "Add --advertise-tags=tag:server if your tailnet uses ACL tags."
