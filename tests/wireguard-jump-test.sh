#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JUMP="$ROOT/bootstrap/wireguard-jump.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -x "$JUMP" ]] || fail "wireguard-jump.sh is not executable"
bash -n "$JUMP"

ROOTFS="$TMP/rootfs"
BIN="$TMP/bin"
mkdir -p "$ROOTFS/etc" "$BIN"
: > "$ROOTFS/etc/passwd"

cat > "$BIN/useradd" <<'SH'
#!/usr/bin/env bash
user=${*: -1}
printf '%s:x:999:999::%s:/usr/sbin/nologin\n' "$user" "$WG_ROOT/home/$user" >> "$WG_ROOT/etc/passwd"
SH
cat > "$BIN/id" <<'SH'
#!/usr/bin/env bash
grep -q "^${*: -1}:" "$WG_ROOT/etc/passwd"
SH
cat > "$BIN/getent" <<'SH'
#!/usr/bin/env bash
grep "^$2:" "$WG_ROOT/etc/passwd"
SH
cat > "$BIN/chown" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$BIN/ssh-keygen" <<'SH'
#!/usr/bin/env bash
case "$(cat "${*: -1}")" in
  ssh-ed25519\ AAAAC3NzaC1lZDI1NTE5*) exit 0 ;;
  *) exit 1 ;;
esac
SH
chmod +x "$BIN"/*
export WG_ROOT="$ROOTFS" PATH="$BIN:/usr/bin:/bin"

KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJumpTestKeyOnlyForSandbox macbook'
AUTH="$ROOTFS/home/wgjump/.ssh/authorized_keys"

if "$JUMP" set 'ssh-rsa not-a-key' 2>/dev/null; then fail "invalid key accepted"; fi
if "$JUMP" set "$KEY"$'\n'"$KEY" 2>/dev/null; then fail "multi-line key accepted"; fi

"$JUMP" set "$KEY"
[[ -f "$AUTH" ]] || fail "authorized_keys missing"
expected="restrict,port-forwarding,permitopen=\"10.88.0.2:22\" $KEY"
[[ $(cat "$AUTH") == "$expected" ]] || fail "authorized_keys line wrong: $(cat "$AUTH")"
[[ $(stat -c '%a' "$AUTH") == 600 ]] || fail "authorized_keys mode not 600"
grep -q '^wgjump:.*:/usr/sbin/nologin$' "$ROOTFS/etc/passwd" || fail "wgjump must use nologin"

"$JUMP" set "$KEY"
[[ $(grep -c '^wgjump:' "$ROOTFS/etc/passwd") == 1 ]] || fail "user duplicated"
[[ $(wc -l < "$AUTH") == 1 ]] || fail "key duplicated"

"$JUMP" revoke
[[ ! -s "$AUTH" ]] || fail "revoke left keys"

GUIDE="$ROOT/docs/operations/wireguard-remote-access.md"
grep -Fq 'ProxyJump vps-jump' "$GUIDE" || fail "guide missing ProxyJump config"
grep -Fq 'LocalForward 5901 127.0.0.1:5900' "$GUIDE" || fail "guide missing Screen Sharing forward"
grep -Fq 'wireguard-jump.sh' "$ROOT/docs/RUNBOOK.md" || fail "runbook missing jump procedure"

printf 'PASS: WireGuard SSH jump user is restricted and idempotent\n'
