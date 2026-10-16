#!/usr/bin/env bash
# Manage fixed WireGuard peers without handling client private keys.
set -euo pipefail
umask 077

WG_INTERFACE="wg0"
WG_ROOT=${WG_ROOT:-}
WG_DIR="$WG_ROOT/etc/wireguard"
WG_CONFIG="$WG_DIR/$WG_INTERFACE.conf"

log() { printf '[wireguard-peer] %s\n' "$*"; }
die() { printf '[wireguard-peer] ERROR: %s\n' "$*" >&2; exit 1; }
require_root() { [[ -n "$WG_ROOT" || ${EUID:-$(id -u)} -eq 0 ]] || die "run as root"; }

peer_address() {
  case $1 in
    omarchy) printf '10.88.0.2/32\n' ;;
    macbook) printf '10.88.0.3/32\n' ;;
    *) die "peer must be omarchy or macbook" ;;
  esac
}

peer_routes() {
  case $1 in
    omarchy) printf '10.88.0.1/32, 10.88.0.3/32\n' ;;
    macbook) printf '10.88.0.1/32, 10.88.0.2/32\n' ;;
    *) die "peer must be omarchy or macbook" ;;
  esac
}

validate_public_key() {
  local key=$1 byte_count
  [[ $key =~ ^[A-Za-z0-9+/]{43}=$ ]] || die "invalid WireGuard public key"
  byte_count=$(printf '%s' "$key" | base64 -d 2>/dev/null | wc -c) || die "invalid WireGuard public key"
  [[ $byte_count -eq 32 ]] || die "invalid WireGuard public key"
}

without_peer() {
  local name=$1 source=$2 destination=$3
  awk -v marker="# peer:$name" '
    $0 == marker { skip=1; next }
    skip && /^# peer:/ { skip=0 }
    skip && /^\[Peer\]$/ { next }
    skip && /^$/ { skip=0; next }
    !skip { print }
  ' "$source" > "$destination"
}

# wg-quick only accepts paths named <interface>.conf, so strip a copy.
strip_config() {
  local source=$1 scratch status=0
  scratch=$(mktemp -d "$WG_DIR/.strip.XXXXXX")
  cp "$source" "$scratch/$WG_INTERFACE.conf"
  wg-quick strip "$scratch/$WG_INTERFACE.conf" || status=$?
  rm -rf "$scratch"
  return "$status"
}

apply_candidate() {
  local candidate=$1 runtime
  strip_config "$candidate" >/dev/null || die "candidate configuration invalid"
  chmod 600 "$candidate"
  if cmp -s "$candidate" "$WG_CONFIG"; then
    rm -f "$candidate"
    return 1
  fi
  if systemctl is-active --quiet "wg-quick@$WG_INTERFACE"; then
    runtime=$(mktemp "$WG_DIR/.wg0.runtime.XXXXXX")
    trap 'rm -f "${runtime:-}"' RETURN
    strip_config "$candidate" > "$runtime"
    if ! wg syncconf "$WG_INTERFACE" "$runtime"; then
      rm -f "$runtime"
      trap - RETURN
      die "runtime sync failed; persistent configuration unchanged"
    fi
    rm -f "$runtime"
    trap - RETURN
  fi
  mv "$candidate" "$WG_CONFIG"
  return 0
}

add_peer() {
  local name=$1 public_key=$2 address candidate base
  validate_public_key "$public_key"
  address=$(peer_address "$name")
  if awk -v marker="# peer:$name" -v key="$public_key" -v address="$address" '
    $0 == marker { target=1; next }
    target && $0 == "PublicKey = " key { key_ok=1 }
    target && $0 == "AllowedIPs = " address { address_ok=1 }
    target && /^# peer:/ { exit }
    END { exit !(key_ok && address_ok) }
  ' "$WG_CONFIG"; then
    log "$name already current"
    return
  fi
  candidate=$(mktemp "$WG_DIR/.wg0.conf.XXXXXX")
  base=$(mktemp "$WG_DIR/.wg0.base.XXXXXX")
  trap 'rm -f "${candidate:-}" "${base:-}"' RETURN
  without_peer "$name" "$WG_CONFIG" "$base"
  if grep -Fqx "PublicKey = $public_key" "$base"; then
    die "public key already assigned to another peer"
  fi
  cat "$base" > "$candidate"
  [[ ! -s "$candidate" || $(tail -c1 "$candidate" | wc -l) -eq 1 ]] || printf '\n' >> "$candidate"
  cat >> "$candidate" <<EOF

# peer:$name
[Peer]
PublicKey = $public_key
AllowedIPs = $address
EOF
  if apply_candidate "$candidate"; then
    log "$name enrolled at $address"
  else
    log "$name already current"
  fi
  rm -f "$base"
  trap - RETURN
}

revoke_peer() {
  local name=$1 candidate
  peer_address "$name" >/dev/null
  candidate=$(mktemp "$WG_DIR/.wg0.conf.XXXXXX")
  trap 'rm -f "${candidate:-}"' RETURN
  without_peer "$name" "$WG_CONFIG" "$candidate"
  if apply_candidate "$candidate"; then
    log "$name revoked"
  else
    log "$name already absent"
  fi
  trap - RETURN
}

render_peer() {
  local name=$1 server_public_key=$2 endpoint=${3:-}
  [[ -n $endpoint ]] || die "endpoint required"
  validate_public_key "$server_public_key"
  cat <<EOF
# Secret after replacing <PRIVATE_KEY>; store outside Git with mode 0600.
[Interface]
PrivateKey = <PRIVATE_KEY>
Address = $(peer_address "$name")

[Peer]
PublicKey = $server_public_key
Endpoint = $endpoint
AllowedIPs = $(peer_routes "$name")
PersistentKeepalive = 25
EOF
}

case ${1:-} in
  add)
    require_root
    [[ $# -eq 3 ]] || die "usage: $0 add <omarchy|macbook> <public-key>"
    [[ -s $WG_CONFIG ]] || die "$WG_CONFIG missing; install server first"
    add_peer "$2" "$3"
    ;;
  revoke)
    require_root
    [[ $# -eq 2 ]] || die "usage: $0 revoke <omarchy|macbook>"
    [[ -s $WG_CONFIG ]] || die "$WG_CONFIG missing; install server first"
    revoke_peer "$2"
    ;;
  render)
    [[ $# -eq 4 ]] || die "usage: $0 render <omarchy|macbook> <server-public-key> <endpoint>"
    render_peer "$2" "$3" "$4"
    ;;
  *) die "usage: $0 <add|revoke|render> ..." ;;
esac
