#!/usr/bin/env bash
# Manage the restricted SSH jump user for clients that cannot run WireGuard.
# The user has no shell and its single key may only open 10.88.0.2:22.
set -euo pipefail
umask 077

JUMP_USER="wgjump"
JUMP_TARGET="10.88.0.2:22"
WG_ROOT=${WG_ROOT:-}

die() { printf '[wireguard-jump] ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[wireguard-jump] %s\n' "$*"; }
[[ -n "$WG_ROOT" || ${EUID:-$(id -u)} -eq 0 ]] || die "run as root"

ensure_user() {
  id "$JUMP_USER" >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin "$JUMP_USER"
}

home_dir() { getent passwd "$JUMP_USER" | cut -d: -f6; }

set_key() {
  local key=$1 check ssh_dir auth
  [[ $key != *$'\n'* ]] || die "key must be a single line"
  [[ $key =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+(\ .*)?$ ]] || die "only ssh-ed25519 public keys are accepted"
  check=$(mktemp)
  printf '%s\n' "$key" > "$check"
  ssh-keygen -l -f "$check" >/dev/null 2>&1 || { rm -f "$check"; die "invalid SSH public key"; }
  rm -f "$check"
  ensure_user
  ssh_dir="$(home_dir)/.ssh"
  auth="$ssh_dir/authorized_keys"
  install -d -m 700 "$ssh_dir"
  printf 'restrict,port-forwarding,permitopen="%s" %s\n' "$JUMP_TARGET" "$key" > "$auth.tmp"
  chmod 600 "$auth.tmp"
  mv "$auth.tmp" "$auth"
  chown -R "$JUMP_USER:$JUMP_USER" "$ssh_dir"
  log "$JUMP_USER may only forward to $JUMP_TARGET"
}

revoke() {
  id "$JUMP_USER" >/dev/null 2>&1 || { log "$JUMP_USER absent"; return; }
  : > "$(home_dir)/.ssh/authorized_keys" 2>/dev/null || true
  log "$JUMP_USER keys revoked"
}

case ${1:-} in
  set) [[ $# -eq 2 ]] || die "usage: $0 set '<ssh-ed25519 public key>'"; set_key "$2" ;;
  revoke) revoke ;;
  *) die "usage: $0 <set|revoke>" ;;
esac
