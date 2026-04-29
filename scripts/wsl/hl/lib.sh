#!/usr/bin/env bash
# Shared helpers for hl (homelab terminal manager). Source me; do not execute.

# ---- paths ---------------------------------------------------------
# resolve the repo root from this file, following symlinks so that
# /usr/local/bin/hl -> <repo>/scripts/wsl/hl/hl still finds the repo.
__hl_self="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
HL_BIN_DIR="$(cd "$(dirname "$__hl_self")" && pwd)"
HL_REPO="$(cd "$HL_BIN_DIR/../../.." && pwd)"
unset __hl_self
export HL_BIN_DIR HL_REPO

# ---- colors --------------------------------------------------------
if [ -t 1 ] && [ "${HL_NO_COLOR:-0}" != "1" ] && [ "${NO_COLOR:-}" = "" ]; then
	C_RESET=$'\033[0m'
	C_BOLD=$'\033[1m'
	C_DIM=$'\033[2m'
	C_RED=$'\033[31m'
	C_GREEN=$'\033[32m'
	C_YELLOW=$'\033[33m'
	C_BLUE=$'\033[34m'
	C_MAGENTA=$'\033[35m'
	C_CYAN=$'\033[36m'
else
	C_RESET=''; C_BOLD=''; C_DIM=''
	C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_MAGENTA=''; C_CYAN=''
fi

# ---- terminal width ------------------------------------------------
hl_cols() {
	local c
	c=$(tput cols 2>/dev/null) || c="${COLUMNS:-80}"
	[ -z "$c" ] && c=80
	echo "$c"
}

# ---- output helpers ------------------------------------------------
hl_rule() { local w; w=$(hl_cols); printf "%${w}s\n" '' | tr ' ' '-'; }
hl_dbl()  { local w; w=$(hl_cols); printf "%${w}s\n" '' | tr ' ' '='; }

hl_h1() {
	printf "%s%s%s\n" "$C_BOLD" "$1" "$C_RESET"
	hl_rule
}

hl_info()  { printf "%s==>%s %s\n"  "$C_BLUE"   "$C_RESET" "$*"; }
hl_ok()    { printf "%s[ok]%s %s\n" "$C_GREEN"  "$C_RESET" "$*"; }
hl_warn()  { printf "%s[!]%s  %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
hl_err()   { printf "%s[err]%s %s\n" "$C_RED"   "$C_RESET" "$*" >&2; }
hl_die()   { hl_err "$*"; exit 1; }

# tag without padding-affecting color codes
hl_tag() {
	case "$1" in
		ok)    printf "%s[ok]%s"   "$C_GREEN"  "$C_RESET" ;;
		warn)  printf "%s[warn]%s" "$C_YELLOW" "$C_RESET" ;;
		err)   printf "%s[err]%s"  "$C_RED"    "$C_RESET" ;;
		off)   printf "%s[off]%s"  "$C_DIM"    "$C_RESET" ;;
		*)     printf "[%s]" "$1" ;;
	esac
}

# ---- confirm -------------------------------------------------------
hl_confirm() {
	local prompt="${1:-Proceed?}" ans
	if [ ! -t 0 ]; then return 0; fi   # non-interactive: accept
	read -r -p "$prompt [y/N] " ans
	case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ---- fzf wrapper ---------------------------------------------------
hl_pick() {
	local prompt="${1:-pick}"
	if command -v fzf >/dev/null 2>&1 && [ -r /dev/tty ]; then
		fzf --prompt="$prompt> " --height=40% --reverse --border --no-info \
		    --color='border:dim,prompt:bold'
	else
		# fallback: numbered prompt
		local lines=() i=1 idx
		while IFS= read -r line; do lines+=("$line"); done
		[ "${#lines[@]}" -gt 0 ] || return 1
		[ -r /dev/tty ] && [ -w /dev/tty ] || return 1
		printf "%s\n" "${lines[@]}" | nl -w2 -s'  ' >/dev/tty
		printf "%s> select #: " "$prompt" >/dev/tty
		read -r idx </dev/tty
		[[ "${idx:-}" =~ ^[0-9]+$ ]] || return 1
		[ "$idx" -ge 1 ] && [ "$idx" -le "${#lines[@]}" ] || return 1
		printf "%s\n" "${lines[$((idx-1))]}"
	fi
}

# ---- stack discovery -----------------------------------------------
# Echo the name of every compose stack found under $HL_REPO/docker/.
hl_stacks() {
	[ -d "$HL_REPO/docker" ] || return 0
	local d cf
	for d in "$HL_REPO"/docker/*/; do
		[ -d "$d" ] || continue
		cf="$d/compose.yaml"
		[ -f "$cf" ] || cf="$d/compose.yml"
		[ -f "$cf" ] || continue
		basename "${d%/}"
	done
}

hl_stack_path() {
	local name="$1"
	if   [ -f "$HL_REPO/docker/$name/compose.yaml" ]; then echo "$HL_REPO/docker/$name/compose.yaml"
	elif [ -f "$HL_REPO/docker/$name/compose.yml"  ]; then echo "$HL_REPO/docker/$name/compose.yml"
	else return 1
	fi
}

# Treat a stack as GPU-bound if its compose file requests an NVIDIA
# device or carries the explicit x-homelab-gpu: true marker.
hl_stack_is_gpu() {
	local cf
	cf=$(hl_stack_path "$1") || return 1
	grep -qE '(driver:[[:space:]]*nvidia|x-homelab-gpu:[[:space:]]*true)' "$cf"
}

hl_resolve_stack() {
	# Resolve a stack name (allowing fuzzy via fzf if ambiguous).
	local q="${1:-}"
	if [ -n "$q" ] && hl_stack_path "$q" >/dev/null 2>&1; then echo "$q"; return 0; fi
	if [ -n "$q" ]; then
		hl_err "stack not found: $q"
		return 1
	fi
	local picked
	picked=$(hl_stacks | hl_pick "stack")
	[ -z "$picked" ] && return 1
	echo "$picked"
}

# ---- environment probes --------------------------------------------
hl_have_gpu()     { command -v nvidia-smi  >/dev/null 2>&1; }
hl_have_ts()      { command -v tailscale   >/dev/null 2>&1; }
hl_have_docker()  { command -v docker      >/dev/null 2>&1; }
hl_docker_ready() { hl_have_docker && docker info >/dev/null 2>&1; }
hl_systemd_running() { [ "$(cat /proc/1/comm 2>/dev/null)" = "systemd" ]; }

# ---- usage helper --------------------------------------------------
hl_usage_die() {
	# print message to stderr and exit 2
	printf "%s\n" "$*" >&2
	exit 2
}
