#!/usr/bin/env bash
# 03-tailscale.sh -- install Tailscale inside WSL.
#
# Only needed if mirrored networking on the Windows host cannot expose
# WSL2 services on the tailnet. With mirrored networking plus Tailscale
# on Windows, you can usually skip this entirely.

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
