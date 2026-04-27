#!/usr/bin/env bash
# 01-link-dotfiles.sh -- symlink dotfiles from the repo into $HOME.
# Re-runnable. Existing files are moved into ~/.dotfiles-backup-<ts>/.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

require_not_root

DOTFILES="$REPO_ROOT/dotfiles"
BACKUP="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

link() {
	local src="$1" dst="$2"
	[ -e "$src" ] || die "source missing: $src"
	if [ -L "$dst" ]; then
		rm -f "$dst"
	elif [ -e "$dst" ]; then
		mkdir -p "$BACKUP"
		mv "$dst" "$BACKUP/"
		warn "backed up $dst -> $BACKUP/"
	fi
	ln -s "$src" "$dst"
	ok "linked $dst -> $src"
}

log "Linking dotfiles from $DOTFILES"
link "$DOTFILES/tmux.conf"    "$HOME/.tmux.conf"
link "$DOTFILES/inputrc"      "$HOME/.inputrc"
link "$DOTFILES/bashrc.local" "$HOME/.bashrc.local"

# Source bashrc.local from .bashrc (idempotent)
if ! grep -q 'bashrc.local' "$HOME/.bashrc" 2>/dev/null; then
	printf '\n# homelab\n[ -f ~/.bashrc.local ] && . ~/.bashrc.local\n' >> "$HOME/.bashrc"
	ok "appended bashrc.local source line to ~/.bashrc"
fi

# .gitconfig is a template -- copy if absent, never overwrite a real one.
if [ ! -f "$HOME/.gitconfig" ]; then
	cp "$DOTFILES/gitconfig.template" "$HOME/.gitconfig"
	warn "copied gitconfig template to ~/.gitconfig -- edit user.name and user.email"
else
	ok "~/.gitconfig already exists, leaving alone"
fi

# SSH client config -- only link if user has none yet.
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [ ! -e "$HOME/.ssh/config" ]; then
	link "$DOTFILES/ssh/config" "$HOME/.ssh/config"
	chmod 600 "$HOME/.ssh/config"
fi

[ -d "$BACKUP" ] && warn "originals backed up to $BACKUP"
ok "dotfile linking complete"
