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
assert_not_contains "$INSTALL" 'netfilter-persistent save'
assert_contains "$INSTALL" 'type filter hook forward priority -10'
assert_contains "$INSTALL" 'oifname != "$WG_INTERFACE" drop'
assert_contains "$INSTALL" 'wireguard-firewall.service'

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
case "$op" in
  -N)
    chain=$2
    grep -Fxq -- "CHAIN $chain" "$state" || printf 'CHAIN %s\n' "$chain" >> "$state"
    ;;
  -F)
    chain=$2
    grep -Fvx -- "CHAIN $chain" "$state" | grep -Fv -- "$chain " > "$state.tmp" || true
    printf 'CHAIN %s\n' "$chain" >> "$state.tmp"
    mv "$state.tmp" "$state"
    ;;
  -X)
    chain=$2
    grep -Fvx -- "CHAIN $chain" "$state" | grep -Fv -- "$chain " > "$state.tmp" || true
    mv "$state.tmp" "$state"
    ;;
  -S)
    chain=$2
    grep -F -- "$chain " "$state" | sed "s/^$chain /-A $chain /"
    ;;
  -C|-A|-I|-D)
    chain=$2
    shift 2
    [[ $op != -I || ${1:-} != 1 ]] || shift
    rule="$chain $*"
    case "$op" in
      -C) grep -Fxq -- "$rule" "$state" ;;
      -A) grep -Fxq -- "$rule" "$state" || printf '%s\n' "$rule" >> "$state" ;;
      -I)
        if ! grep -Fxq -- "$rule" "$state"; then
          { printf '%s\n' "$rule"; cat "$state"; } > "$state.tmp"
          mv "$state.tmp" "$state"
        fi ;;
      -D) grep -Fxv -- "$rule" "$state" > "$state.tmp" || true; mv "$state.tmp" "$state" ;;
    esac
    ;;
  *) exit 2 ;;
esac
SH
cat > "$BIN/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$WG_TEST_STATE/log"
case "$1" in
  enable)
    if [[ "$*" == *wireguard-firewall.service* ]]; then
      "$WG_TEST_ROOT/usr/local/sbin/homelab-wireguard-firewall" start
    fi
    ;;
  disable)
    if [[ "$*" == *wireguard-firewall.service* ]]; then
      "$WG_TEST_ROOT/usr/local/sbin/homelab-wireguard-firewall" stop
    fi
    ;;
  is-active|is-enabled) exit 0 ;;
esac
SH
cat > "$BIN/ip" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == "-brief address show dev wg0" ]]; then
  printf 'wg0 UP 10.88.0.1/24\n'
elif [[ "$*" == "link show dev wg0" ]]; then
  exit 1
fi
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
[[ "$1" == strip ]] || exit 0
# Real wg-quick rejects paths whose basename is not <interface>.conf.
[[ $(basename "$2") =~ ^[a-zA-Z0-9_=+.-]{1,15}\.conf$ && $(basename "$2") != .* ]] || {
  echo "wg-quick: The config file must be a valid interface name, followed by .conf" >&2; exit 1; }
cat "$2"
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
cat > "$BIN/nft" <<'SH'
#!/usr/bin/env bash
state="$WG_TEST_STATE/nft"
case "$1" in
  -f) cat > "$state" ;;
  delete) rm -f "$state" ;;
  list) cat "$state" 2>/dev/null || exit 1 ;;
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
assert_count "$STATE/rules" 'homelab-wireguard' 2
assert_contains "$STATE/nft" 'iifname "wg0" oifname != "wg0" drop'

"$INSTALL"
assert_count "$STATE/rules" 'homelab-wireguard' 2

if "$PEER" add omarchy bad-key 2>/dev/null; then
  fail "invalid public key accepted"
fi
"$PEER" add omarchy AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
assert_contains "$ROOTFS/etc/wireguard/wg0.conf" '# peer:omarchy'
assert_contains "$ROOTFS/etc/wireguard/wg0.conf" 'AllowedIPs = 10.88.0.2/32'
log_before=$(wc -l < "$STATE/log")
"$PEER" add omarchy AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
assert_count "$ROOTFS/etc/wireguard/wg0.conf" '# peer:omarchy' 1
[[ $(wc -l < "$STATE/log") == "$log_before" ]] || fail "unchanged peer triggered runtime sync"
"$PEER" add macbook AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE=
if "$PEER" add omarchy AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE= 2>/dev/null; then
  fail "duplicate public key accepted"
fi
"$PEER" revoke macbook
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
[[ ! -e "$STATE/nft" ]] || fail "nft table not removed"
assert_file "$ROOTFS/etc/wireguard/server.key"

OMARCHY="$ROOT/docs/examples/wireguard/omarchy.conf.example"
MACBOOK="$ROOT/docs/examples/wireguard/macbook.conf.example"
GUIDE="$ROOT/docs/operations/wireguard-remote-access.md"
ADR="$ROOT/docs/adr/007-host-wireguard-hub.md"
for file in "$OMARCHY" "$MACBOOK" "$GUIDE" "$ADR"; do
  assert_file "$file"
done
assert_contains "$OMARCHY" 'Address = 10.88.0.2/32'
assert_contains "$OMARCHY" 'AllowedIPs = 10.88.0.1/32, 10.88.0.3/32'
assert_contains "$MACBOOK" 'Address = 10.88.0.3/32'
assert_contains "$MACBOOK" 'AllowedIPs = 10.88.0.1/32, 10.88.0.2/32'
assert_contains "$OMARCHY" 'PersistentKeepalive = 25'
assert_contains "$MACBOOK" 'PersistentKeepalive = 25'
assert_contains "$GUIDE" 'address=127.0.0.1'
assert_contains "$GUIDE" 'ssh -N -L 5900:127.0.0.1:5900'
assert_contains "$ROOT/.gitignore" '*.wireguard.conf'
for file in "$ROOT/README.md" "$ROOT/docs/RUNBOOK.md" "$ROOT/docs/security/security.md" "$ROOT/docs/networking.md"; do
  assert_contains "$file" 'wireguard-remote-access.md'
done
if grep -REq '^PrivateKey = [A-Za-z0-9+/]{43}=$' "$ROOT/docs"; then
  fail "documentation contains a real-looking private key"
fi

printf 'PASS: WireGuard host scripts satisfy safety and idempotency contract\n'
