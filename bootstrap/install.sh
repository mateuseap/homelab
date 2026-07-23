#!/usr/bin/env bash
# homelab bootstrap — turns a fresh Ubuntu/Debian VPS into the full platform.
# Idempotent: safe to re-run. Requires: root (or sudo), curl.
#
# Usage: sudo bash install.sh
set -euo pipefail

REPO_URL="https://github.com/mateuseap/homelab"
ARGOCD_VERSION="v2.12.6"

log() { echo -e "\033[1;32m[homelab]\033[0m $*"; }

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
if ! $KUBECTL get ns argocd >/dev/null 2>&1; then
  log "Installing ArgoCD ${ARGOCD_VERSION}..."
  $KUBECTL create namespace argocd
  $KUBECTL apply -n argocd -f \
    "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
else
  log "ArgoCD namespace exists, skipping install."
fi

# Trim for 1 vCPU / 4GB: no dex (no SSO needed), no notifications controller.
$KUBECTL -n argocd scale deployment argocd-dex-server --replicas=0 || true
$KUBECTL -n argocd scale deployment argocd-notifications-controller --replicas=0 || true

# Serve the UI behind Traefik (TLS terminates at the ingress).
$KUBECTL -n argocd patch configmap argocd-cmd-params-cm \
  --type merge -p '{"data":{"server.insecure":"true"}}'
$KUBECTL -n argocd rollout restart deployment argocd-server

log "Waiting for ArgoCD server..."
$KUBECTL -n argocd rollout status deployment argocd-server --timeout=300s

# ── 3. Root app-of-apps — from here on, git is the source of truth ──────────
log "Applying root application (GitOps takes over)..."
$KUBECTL apply -f "$(dirname "$0")/root.yaml"

log "Done. Next steps:"
log "  1. Point *.lab.mateuseap.com (A record) at this machine's IP."
log "  2. Initial admin password:"
log "     k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
log "  3. Seal your secrets (see docs/RUNBOOK.md § Secrets)."
log "  4. Watch everything come up at https://argo.lab.mateuseap.com"
