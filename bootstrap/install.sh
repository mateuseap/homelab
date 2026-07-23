#!/usr/bin/env bash
# homelab bootstrap: turns a fresh Ubuntu/Debian VPS into the full platform.
# Idempotent: safe to re-run. Requires: root (or sudo), curl.
#
# Usage: sudo bash install.sh
set -euo pipefail

REPO_URL="https://github.com/mateuseap/homelab"
# "stable" tracks the latest stable release; older pins hit diff-schema bugs
# against current Kubernetes (e.g. .status.terminatingReplicas on 2.12).
ARGOCD_VERSION="stable"

log() { echo -e "\033[1;32m[homelab]\033[0m $*"; }

# ── 0. Host hardening (swap, firewall, fail2ban, SSH). Idempotent. ──────────
harden_host() {
  export DEBIAN_FRONTEND=noninteractive

  # 2 GB swap. Prometheus and image builds spike memory; without swap the node
  # OOM-locked once. Low swappiness so it only engages under real pressure.
  if ! swapon --show | grep -q swapfile; then
    log "Adding 2 GB swap..."
    fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    sysctl -w vm.swappiness=10 >/dev/null
    grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
  fi

  # fail2ban plus persistent iptables tooling.
  if ! command -v fail2ban-client >/dev/null 2>&1 || ! command -v netfilter-persistent >/dev/null 2>&1; then
    log "Installing fail2ban and iptables-persistent..."
    echo 'iptables-persistent iptables-persistent/autosave_v4 boolean false' | debconf-set-selections
    echo 'iptables-persistent iptables-persistent/autosave_v6 boolean false' | debconf-set-selections
    apt-get update -qq && apt-get install -y -qq netfilter-persistent iptables-persistent fail2ban
  fi
  install -d /etc/fail2ban/jail.d
  cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
port = 22
maxretry = 4
bantime = 1h
findtime = 10m
EOF
  systemctl enable --now fail2ban >/dev/null 2>&1 || true

  # node-exporter (:9100) serves unauthenticated host metrics. Restrict it to
  # the pod network, loopback, and the node itself; drop the public internet.
  # Traffic to the node's own IP routes via lo, which is what the kubelet
  # liveness probe uses, so -i lo must be allowed or node-exporter crashloops.
  allow9100() { iptables -C INPUT $1 -p tcp --dport 9100 -j ACCEPT 2>/dev/null || iptables -I INPUT $1 -p tcp --dport 9100 -j ACCEPT; }
  iptables -C INPUT -p tcp --dport 9100 -j DROP 2>/dev/null || iptables -A INPUT -p tcp --dport 9100 -j DROP
  allow9100 "-i lo"
  allow9100 "-s 127.0.0.0/8"
  allow9100 "-s 10.42.0.0/16"   # k3s default pod CIDR
  netfilter-persistent save >/dev/null 2>&1 || true

  # SSH key-only, but only once a key is present, never lock out a fresh box.
  if [ -s /root/.ssh/authorized_keys ] || [ -s "${HOME}/.ssh/authorized_keys" ]; then
    if [ ! -f /etc/ssh/sshd_config.d/00-security-hardening.conf ]; then
      log "Enabling SSH key-only auth (authorized_keys present)..."
      cat > /etc/ssh/sshd_config.d/00-security-hardening.conf <<'EOF'
PasswordAuthentication no
PermitRootLogin prohibit-password
KbdInteractiveAuthentication no
EOF
      sshd -t && { systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true; }
    fi
  else
    log "SSH still allows passwords: no authorized_keys yet. Add your key, then re-run to lock it down."
  fi
}

log "Hardening host..."
harden_host

# ── 1. k3s (includes Traefik ingress, CoreDNS, local-path storage) ──────────
if ! command -v k3s >/dev/null 2>&1; then
  log "Installing k3s..."
  curl -sfL https://get.k3s.io | sh -
else
  log "k3s already installed, skipping."
fi
export KUBECTL="k3s kubectl"

log "Waiting for node to be Ready..."
until $KUBECTL wait --for=condition=Ready node --all --timeout=300s >/dev/null 2>&1; do sleep 5; done

# ── 2. ArgoCD ───────────────────────────────────────────────────────────────
log "Installing/upgrading ArgoCD (${ARGOCD_VERSION})..."
$KUBECTL get ns argocd >/dev/null 2>&1 || $KUBECTL create namespace argocd
# apply is idempotent: fresh install and upgrade are the same operation
$KUBECTL apply -n argocd -f \
  "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# Trim for 1 vCPU / 4GB: no dex (no SSO needed), no notifications controller.
$KUBECTL -n argocd scale deployment argocd-dex-server --replicas=0 || true
$KUBECTL -n argocd scale deployment argocd-notifications-controller --replicas=0 || true

# Serve the UI behind Traefik (TLS terminates at the ingress).
$KUBECTL -n argocd patch configmap argocd-cmd-params-cm \
  --type merge -p '{"data":{"server.insecure":"true"}}'
$KUBECTL -n argocd rollout restart deployment argocd-server

log "Waiting for ArgoCD server..."
$KUBECTL -n argocd rollout status deployment argocd-server --timeout=300s

# ── 3. Root app-of-apps, from here on, git is the source of truth ──────────
log "Applying root application (GitOps takes over)..."
$KUBECTL apply -f "$(dirname "$0")/root.yaml"

log "Done. Next steps:"
log "  1. Point *.lab.mateuseap.com (A record) at this machine's IP."
log "  2. Initial admin password:"
log "     k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
log "  3. Seal your secrets (see docs/RUNBOOK.md § Secrets)."
log "  4. Watch everything come up at https://argo.lab.mateuseap.com"
