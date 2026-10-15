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
RULE_COMMENT="homelab-wireguard"

log() { printf '[wireguard] %s\n' "$*"; }
die() { printf '[wireguard] ERROR: %s\n' "$*" >&2; exit 1; }
require_root() { [[ -n "$WG_ROOT" || ${EUID:-$(id -u)} -eq 0 ]] || die "run as root"; }

rule() {
  local chain=$1
  shift
  if ! iptables -C "$chain" "$@" 2>/dev/null; then
    iptables -A "$chain" "$@"
  fi
}

remove_rule() {
  local chain=$1
  shift
  while iptables -C "$chain" "$@" 2>/dev/null; do
    iptables -D "$chain" "$@"
  done
}

install_firewall() {
  rule INPUT -p udp --dport "$WG_PORT" -m comment --comment "$RULE_COMMENT-input" -j ACCEPT
  rule FORWARD -i "$WG_INTERFACE" -o "$WG_INTERFACE" -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment "$RULE_COMMENT-established" -j ACCEPT
  rule FORWARD -i "$WG_INTERFACE" -o "$WG_INTERFACE" -m comment --comment "$RULE_COMMENT-peers" -j ACCEPT
  rule FORWARD -i "$WG_INTERFACE" '!' -o "$WG_INTERFACE" -m comment --comment "$RULE_COMMENT-isolation" -j DROP
  netfilter-persistent save >/dev/null
}

remove_firewall() {
  remove_rule INPUT -p udp --dport "$WG_PORT" -m comment --comment "$RULE_COMMENT-input" -j ACCEPT
  remove_rule FORWARD -i "$WG_INTERFACE" -o "$WG_INTERFACE" -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment "$RULE_COMMENT-established" -j ACCEPT
  remove_rule FORWARD -i "$WG_INTERFACE" -o "$WG_INTERFACE" -m comment --comment "$RULE_COMMENT-peers" -j ACCEPT
  remove_rule FORWARD -i "$WG_INTERFACE" '!' -o "$WG_INTERFACE" -m comment --comment "$RULE_COMMENT-isolation" -j DROP
  netfilter-persistent save >/dev/null
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
  iptables -C INPUT -p udp --dport "$WG_PORT" -m comment --comment "$RULE_COMMENT-input" -j ACCEPT 2>/dev/null || die "input rule missing"
  iptables -C FORWARD -i "$WG_INTERFACE" -o "$WG_INTERFACE" -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment "$RULE_COMMENT-established" -j ACCEPT 2>/dev/null || die "established rule missing"
  iptables -C FORWARD -i "$WG_INTERFACE" -o "$WG_INTERFACE" -m comment --comment "$RULE_COMMENT-peers" -j ACCEPT 2>/dev/null || die "peer forwarding rule missing"
  iptables -C FORWARD -i "$WG_INTERFACE" '!' -o "$WG_INTERFACE" -m comment --comment "$RULE_COMMENT-isolation" -j DROP 2>/dev/null || die "isolation rule missing"
  systemctl is-enabled --quiet "wg-quick@$WG_INTERFACE" || die "service not enabled"
  systemctl is-active --quiet "wg-quick@$WG_INTERFACE" || die "service not active"
  log "configuration healthy"
}

uninstall_service() {
  systemctl disable --now "wg-quick@$WG_INTERFACE" >/dev/null 2>&1 || true
  remove_firewall
  log "service disabled and WireGuard rules removed; keys and configuration retained"
}

install_service() {
  if ! command -v wg >/dev/null 2>&1 && [[ ${WG_SKIP_PACKAGE_INSTALL:-0} != 1 ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq wireguard-tools
  fi
  command -v wg >/dev/null 2>&1 || die "wg command unavailable"
  command -v wg-quick >/dev/null 2>&1 || die "wg-quick command unavailable"
  command -v netfilter-persistent >/dev/null 2>&1 || die "netfilter-persistent unavailable"

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

  install_firewall
  systemctl enable --now "wg-quick@$WG_INTERFACE" >/dev/null
  check
}

require_root
case ${1:-install} in
  install) install_service ;;
  --check) check ;;
  --uninstall) uninstall_service ;;
  *) die "usage: $0 [--check|--uninstall]" ;;
esac
