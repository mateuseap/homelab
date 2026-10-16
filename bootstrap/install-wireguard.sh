#!/usr/bin/env bash
# Install a host-level WireGuard hub without changing existing firewall policy.
set -euo pipefail
umask 077

WG_INTERFACE="wg0"
WG_ADDRESS="10.88.0.1/24"
WG_SUBNET="10.88.0.0/24"
WG_PORT="51820"
WG_ROOT=${WG_ROOT:-}
WG_DIR="$WG_ROOT/etc/wireguard"
WG_CONFIG="$WG_DIR/$WG_INTERFACE.conf"
WG_PRIVATE_KEY="$WG_DIR/server.key"
SYSCTL_FILE="$WG_ROOT/etc/sysctl.d/90-wireguard-forwarding.conf"
FIREWALL_SCRIPT="$WG_ROOT/usr/local/sbin/homelab-wireguard-firewall"
FIREWALL_UNIT="$WG_ROOT/etc/systemd/system/wireguard-firewall.service"
NFT_TABLE="homelab_wireguard"
RULE_COMMENT="homelab-wireguard"

log() { printf '[wireguard] %s\n' "$*"; }
die() { printf '[wireguard] ERROR: %s\n' "$*" >&2; exit 1; }
require_root() { [[ -n "$WG_ROOT" || ${EUID:-$(id -u)} -eq 0 ]] || die "run as root"; }

install_firewall_files() {
  install -d -m 755 "$(dirname "$FIREWALL_SCRIPT")" "$(dirname "$FIREWALL_UNIT")"
  cat > "$FIREWALL_SCRIPT" <<EOF
#!/usr/bin/env bash
# Managed by homelab bootstrap/install-wireguard.sh.
set -euo pipefail
TABLE="$NFT_TABLE"
COMMENT="$RULE_COMMENT"
input_rule=(INPUT -p udp --dport "$WG_PORT" -m comment --comment "\$COMMENT-input" -j ACCEPT)
peer_rule=(FORWARD -i "$WG_INTERFACE" -o "$WG_INTERFACE" -m comment --comment "\$COMMENT-peers" -j ACCEPT)
case \${1:-start} in
  start)
    # Own nftables base chain at priority -10 runs before every iptables
    # filter chain, so k3s and Docker rule ordering cannot bypass isolation.
    nft -f - <<NFT
table inet \$TABLE
delete table inet \$TABLE
table inet \$TABLE {
  chain forward {
    type filter hook forward priority -10; policy accept;
    iifname "$WG_INTERFACE" oifname != "$WG_INTERFACE" drop
  }
}
NFT
    iptables -C "\${input_rule[@]}" 2>/dev/null || iptables -I INPUT 1 "\${input_rule[@]:1}"
    iptables -C "\${peer_rule[@]}" 2>/dev/null || iptables -I FORWARD 1 "\${peer_rule[@]:1}"
    ;;
  stop)
    while iptables -C "\${peer_rule[@]}" 2>/dev/null; do iptables -D "\${peer_rule[@]}"; done
    while iptables -C "\${input_rule[@]}" 2>/dev/null; do iptables -D "\${input_rule[@]}"; done
    nft delete table inet "\$TABLE" 2>/dev/null || true
    ;;
  check)
    nft list chain inet "\$TABLE" forward | grep -Fq 'iifname "$WG_INTERFACE" oifname != "$WG_INTERFACE" drop'
    iptables -C "\${input_rule[@]}"
    iptables -C "\${peer_rule[@]}"
    ;;
  *) echo "usage: \$0 [start|stop|check]" >&2; exit 2 ;;
esac
EOF
  chmod 755 "$FIREWALL_SCRIPT"
  cat > "$FIREWALL_UNIT" <<EOF
[Unit]
Description=WireGuard peer isolation firewall
After=network-online.target netfilter-persistent.service docker.service k3s.service
Wants=network-online.target
Before=wg-quick@$WG_INTERFACE.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$FIREWALL_SCRIPT start
ExecStop=$FIREWALL_SCRIPT stop

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$FIREWALL_UNIT"
}

validate_config() {
  local config=$1
  wg-quick strip "$config" >/dev/null || die "invalid WireGuard configuration"
}

check() {
  [[ -s "$WG_PRIVATE_KEY" ]] || die "server private key missing"
  [[ -s "$WG_CONFIG" ]] || die "configuration missing"
  [[ $(stat -c '%a' "$WG_PRIVATE_KEY") == 600 ]] || die "server private key permissions must be 600"
  validate_config "$WG_CONFIG"
  ip -brief address show dev "$WG_INTERFACE" | grep -Fq '10.88.0.1/24' || die "$WG_INTERFACE address missing"
  [[ $(sysctl -n net.ipv4.ip_forward) == 1 ]] || die "IPv4 forwarding disabled"
  "$FIREWALL_SCRIPT" check >/dev/null 2>&1 || die "WireGuard firewall rules missing"
  systemctl is-enabled --quiet wireguard-firewall.service || die "firewall service not enabled"
  systemctl is-active --quiet wireguard-firewall.service || die "firewall service not active"
  systemctl is-enabled --quiet "wg-quick@$WG_INTERFACE" || die "WireGuard service not enabled"
  systemctl is-active --quiet "wg-quick@$WG_INTERFACE" || die "WireGuard service not active"
  log "configuration healthy"
}

uninstall_service() {
  systemctl disable --now "wg-quick@$WG_INTERFACE" >/dev/null
  if ip link show dev "$WG_INTERFACE" >/dev/null 2>&1; then
    die "$WG_INTERFACE remains active; isolation rules retained"
  fi
  systemctl disable --now wireguard-firewall.service >/dev/null
  log "services disabled and WireGuard rules removed; keys and configuration retained"
}

install_service() {
  local sysctl_existed=0 installed=0
  [[ -e $SYSCTL_FILE ]] && sysctl_existed=1
  cleanup_failure() {
    local status=$?
    (( installed == 0 )) || systemctl disable --now "wg-quick@$WG_INTERFACE" >/dev/null 2>&1 || true
    systemctl disable --now wireguard-firewall.service >/dev/null 2>&1 || true
    (( sysctl_existed == 1 )) || rm -f "$SYSCTL_FILE"
    exit "$status"
  }
  trap cleanup_failure ERR

  if ! command -v wg >/dev/null 2>&1 && [[ ${WG_SKIP_PACKAGE_INSTALL:-0} != 1 ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq wireguard-tools
  fi
  command -v wg >/dev/null 2>&1 || die "wg command unavailable"
  command -v wg-quick >/dev/null 2>&1 || die "wg-quick command unavailable"

  install -d -m 700 "$WG_DIR"
  if [[ ! -s "$WG_PRIVATE_KEY" ]]; then
    wg genkey > "$WG_PRIVATE_KEY"
    chmod 600 "$WG_PRIVATE_KEY"
  fi

  if [[ ! -s "$WG_CONFIG" ]]; then
    local candidate
    candidate=$(mktemp "$WG_DIR/.wg0.conf.XXXXXX")
    cat > "$candidate" <<EOF
[Interface]
Address = $WG_ADDRESS
ListenPort = $WG_PORT
PrivateKey = $(cat "$WG_PRIVATE_KEY")
EOF
    chmod 600 "$candidate"
    validate_config "$candidate"
    mv "$candidate" "$WG_CONFIG"
  else
    chmod 600 "$WG_CONFIG"
    validate_config "$WG_CONFIG"
  fi

  install -d -m 755 "$(dirname "$SYSCTL_FILE")"
  printf 'net.ipv4.ip_forward=1\n' > "$SYSCTL_FILE"
  chmod 644 "$SYSCTL_FILE"
  sysctl -q -p "$SYSCTL_FILE"
  install_firewall_files
  systemctl daemon-reload
  systemctl enable --now wireguard-firewall.service >/dev/null
  systemctl enable --now "wg-quick@$WG_INTERFACE" >/dev/null
  installed=1
  check
  trap - ERR
}

require_root
case ${1:-install} in
  install) install_service ;;
  --check) check ;;
  --uninstall) uninstall_service ;;
  *) die "usage: $0 [--check|--uninstall]" ;;
esac
