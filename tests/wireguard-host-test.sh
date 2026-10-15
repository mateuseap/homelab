#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL="$ROOT/bootstrap/install-wireguard.sh"
PEER="$ROOT/bootstrap/wireguard-peer.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "missing $1"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || fail "$1 unexpectedly contains: $2"; }
assert_count() { [[ $(grep -Fc -- "$2" "$1" 2>/dev/null || true) == "$3" ]] || fail "$1 count for '$2' is not $3"; }

[[ -x "$INSTALL" ]] || fail "install-wireguard.sh is not executable"
[[ -x "$PEER" ]] || fail "wireguard-peer.sh is not executable"
bash -n "$INSTALL" "$PEER"

assert_contains "$INSTALL" 'WG_SUBNET="10.88.0.0/24"'
assert_contains "$INSTALL" 'WG_PORT="51820"'
assert_contains "$INSTALL" 'umask 077'
assert_not_contains "$INSTALL" 'MASQUERADE'
assert_not_contains "$INSTALL" '0.0.0.0/0'
assert_not_contains "$INSTALL" '::/0'

ROOTFS="$TMP/rootfs"
STATE="$TMP/state"
BIN="$TMP/bin"
mkdir -p "$ROOTFS" "$STATE" "$BIN"
: > "$STATE/rules"
: > "$STATE/log"

cat > "$BIN/apt-get" <<'SH'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >> "$WG_TEST_STATE/log"
SH
cat > "$BIN/iptables" <<'SH'
#!/usr/bin/env bash
set -e
state="$WG_TEST_STATE/rules"
op=$1
chain=$2
shift 2
rule="$chain $*"
case "$op" in
  -C) grep -Fxq -- "$rule" "$state" ;;
  -A|-I) grep -Fxq -- "$rule" "$state" || printf '%s\n' "$rule" >> "$state" ;;
  -D) grep -Fxv -- "$rule" "$state" > "$state.tmp" || true; mv "$state.tmp" "$state" ;;
  *) exit 2 ;;
esac
SH
cat > "$BIN/netfilter-persistent" <<'SH'
#!/usr/bin/env bash
printf 'netfilter-persistent %s\n' "$*" >> "$WG_TEST_STATE/log"
SH
cat > "$BIN/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$WG_TEST_STATE/log"
case "$1" in
  is-active|is-enabled) exit 0 ;;
esac
SH
cat > "$BIN/ip" <<'SH'
#!/usr/bin/env bash
[[ "$*" == "-brief address show dev wg0" ]] && printf 'wg0 UP 10.88.0.1/24\n'
SH
cat > "$BIN/sysctl" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == "-n net.ipv4.ip_forward" ]]; then
  printf '1\n'
fi
exit 0
SH
cat > "$BIN/wg-quick" <<'SH'
#!/usr/bin/env bash
[[ "$1" == strip ]] && cat "$2"
SH
cat > "$BIN/wg" <<'SH'
#!/usr/bin/env bash
set -e
case "$1" in
  genkey) printf 'SERVER_PRIVATE_KEY\n' ;;
  pubkey)
    read -r key
    case "$key" in
      VALID_PRIVATE_KEY) printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' ;;
      SERVER_PRIVATE_KEY) printf 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=\n' ;;
      *) exit 1 ;;
    esac ;;
  syncconf) printf 'wg syncconf %s\n' "$*" >> "$WG_TEST_STATE/log" ;;
  show) exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$BIN"/*

export WG_ROOT="$ROOTFS" WG_TEST_ROOT="$ROOTFS" WG_TEST_STATE="$STATE"
export PATH="$BIN:/usr/bin:/bin"
export WG_SKIP_PACKAGE_INSTALL=1

"$INSTALL"
assert_file "$ROOTFS/etc/wireguard/server.key"
assert_file "$ROOTFS/etc/wireguard/wg0.conf"
assert_file "$ROOTFS/etc/sysctl.d/90-wireguard-forwarding.conf"
assert_contains "$ROOTFS/etc/wireguard/wg0.conf" 'Address = 10.88.0.1/24'
assert_contains "$ROOTFS/etc/wireguard/wg0.conf" 'ListenPort = 51820'
assert_count "$STATE/rules" 'homelab-wireguard' 4

"$INSTALL"
assert_count "$STATE/rules" 'homelab-wireguard' 4

if "$PEER" add omarchy bad-key 2>/dev/null; then
  fail "invalid public key accepted"
fi
"$PEER" add omarchy AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
assert_contains "$ROOTFS/etc/wireguard/wg0.conf" '# peer:omarchy'
assert_contains "$ROOTFS/etc/wireguard/wg0.conf" 'AllowedIPs = 10.88.0.2/32'
"$PEER" add omarchy AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
assert_count "$ROOTFS/etc/wireguard/wg0.conf" '# peer:omarchy' 1
"$PEER" revoke omarchy
assert_not_contains "$ROOTFS/etc/wireguard/wg0.conf" '# peer:omarchy'

rendered=$($PEER render macbook AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= 179.197.71.43:51820)
grep -Fq 'Address = 10.88.0.3/32' <<< "$rendered" || fail "render missing macbook address"
grep -Fq 'AllowedIPs = 10.88.0.1/32, 10.88.0.2/32' <<< "$rendered" || fail "render missing split routes"
grep -Fq 'PersistentKeepalive = 25' <<< "$rendered" || fail "render missing keepalive"
! grep -Fq 'PrivateKey = SERVER' <<< "$rendered" || fail "render leaked private key"

"$INSTALL" --check
"$INSTALL" --uninstall
assert_count "$STATE/rules" 'homelab-wireguard' 0
assert_file "$ROOTFS/etc/wireguard/server.key"

printf 'PASS: WireGuard host scripts satisfy safety and idempotency contract\n'
