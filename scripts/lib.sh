#!/usr/bin/env bash
# Shared helpers for homelab bootstrap scripts. Source, do not execute.

set -euo pipefail

if [ -t 1 ]; then
	__c_reset=$'\033[0m'
	__c_blue=$'\033[1;34m'
	__c_green=$'\033[1;32m'
	__c_yellow=$'\033[1;33m'
	__c_red=$'\033[1;31m'
else
	__c_reset=''; __c_blue=''; __c_green=''; __c_yellow=''; __c_red=''
fi

log()  { printf "%s==>%s %s\n" "$__c_blue"   "$__c_reset" "$*"; }
ok()   { printf "%s[ok]%s %s\n" "$__c_green"  "$__c_reset" "$*"; }
warn() { printf "%s[!]%s  %s\n" "$__c_yellow" "$__c_reset" "$*"; }
die()  { printf "%s[err]%s %s\n" "$__c_red"   "$__c_reset" "$*" >&2; exit 1; }

require_cmd()      { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }
require_wsl()      { grep -qi microsoft /proc/version 2>/dev/null || die "this script must run inside WSL2"; }
require_root()     { [ "$EUID" -eq 0 ] || die "this script must run as root (try: sudo $0)"; }
require_not_root() { [ "$EUID" -ne 0 ] || die "do not run this script as root"; }
