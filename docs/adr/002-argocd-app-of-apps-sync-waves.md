# ADR-002: ArgoCD App-of-Apps with Sync Waves

**Status:** Accepted  
**Date:** 2026-07-23

## Context

The cluster must be reproducible from git and self-healing: a fresh node should converge to the declared state with no manual `kubectl apply` beyond bootstrap, and any drift should be reverted automatically. The platform also has ordering constraints. Certificates cannot be issued before cert-manager's CRDs exist, application secrets must be decryptable before the pods that mount them start, and the Let's Encrypt issuer must exist before ingresses request certificates.

Two questions had to be answered: what drives the reconciliation, and how is ordering expressed.

## Decision

Use **ArgoCD** in an **app-of-apps** layout, with **sync waves** for ordering.

### App-of-apps

`bootstrap/install.sh` applies exactly one object after installing ArgoCD: the `root` Application (`bootstrap/root.yaml`). `root` watches the `argocd/` directory of this repo, and every Application manifest there becomes a managed app. Adding a project is adding one file to `argocd/` and pushing. From bootstrap onward, git is the source of truth and no further imperative commands are needed.

Every Application (including `root`) runs with `automated: { prune: true, selfHeal: true }`, so deleted resources come back and manual cluster edits are reverted.

### Sync waves

Ordering is expressed with the `argocd.argoproj.io/sync-wave` annotation. Lower waves sync first:

| Wave | Applications | Reason |
|------|--------------|--------|
| 0 | `cert-manager`, `sealed-secrets` | Provide CRDs and secret decryption that everything else depends on |
| 1 | `platform-config`, `monitoring` | `platform-config` needs cert-manager CRDs (the ClusterIssuer); monitoring needs the operator CRDs |
| 2 | `chesskernel`, `pixelhub` | Applications sync last, once the platform is healthy |

## Consequences

- Bootstrap is a single imperative step (install k3s, install ArgoCD, apply `root`); everything else is declarative and reconciled continuously.
- ArgoCD is trimmed for the node: dex and the notifications controller are scaled to zero, and the server runs with `server.insecure=true` so TLS terminates once at Traefik (see ADR-005). These are runtime patches in `install.sh`, not manifests, because they configure ArgoCD itself.
- Some resources need special sync handling. The monitoring Application uses `ServerSideApply=true` because the Prometheus CRDs exceed the client-side apply annotation size limit, and the Prometheus operator's admission webhook certificates are issued by cert-manager rather than the chart's self-deleting patch Jobs, which otherwise race ArgoCD's health check and mark every sync as failed.
- `prune: true` at the app level is powerful and dangerous. Namespaces are deliberately protected from it with a per-object `argocd.argoproj.io/sync-options: Prune=false` annotation (`platform/config/namespaces.yaml`), so removing a namespace line never deletes a live namespace and everything in it.
