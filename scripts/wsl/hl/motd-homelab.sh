#!/usr/bin/env bash
# /etc/update-motd.d/50-homelab
# Installed by scripts/wsl/05-install-tui.sh.
# Replaces noisy default Ubuntu MOTD blocks with a compact homelab banner.

HL=/usr/local/bin/hl
[ -x "$HL" ] || exit 0
"$HL" status --motd 2>/dev/null
