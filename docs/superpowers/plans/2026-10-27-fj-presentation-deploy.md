# Featherweight Java Presentation Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve the pinned Featherweight Java presentation at `https://fj.lab.mateuseap.com` through the existing k3s/ArgoCD platform.

**Architecture:** An nginx Deployment mounts an `emptyDir` at `/usr/share/nginx/html`. A curl initContainer downloads a pinned public `mateuseap/compilers` archive, copies only `seminario-featherweight-java/apresentacao/` into that volume, then exits. A Service and cert-manager Ingress expose port 80; one ArgoCD Application owns the namespace. Removal is deleting two repo paths and letting ArgoCD prune.

**Tech Stack:** Kubernetes, k3s, ArgoCD, nginx:alpine, curlimages/curl, Traefik, cert-manager

**Spec:** Approved chat design: disposable static deployment, `fj.lab.mateuseap.com`, pinned source commit, no image build/PVC/secret.

## Global Constraints

- GitFlow: topic branch from `develop`, PR to `develop`, release PR to `main`; main deploys.
- Every container has CPU/memory requests and memory limits.
- English only; no em dash.
- No plaintext secrets.
- Source archive pinned to compilers commit `c9afc60179dd0ddee4bacf3f47cc357a6a5e5a8b`.
- Only presentation directory is publicly served; no guide or PDF files.

## Review Focus

- Archive download failure must keep nginx unready because initContainer never completes.
- Archive layout must copy `index.html` and `assets/` to web root, not a nested folder.
- Readiness must probe `/index.html` on port 8080.
- Ingress host and TLS secret must both use `fj.lab.mateuseap.com`.
- ArgoCD path and namespace must match `apps/fj-presentation` / `fj-presentation`.

---

### Task 1: Static Application Manifests

**Files:**
- Create: `apps/fj-presentation/deployment.yaml`
- Create: `apps/fj-presentation/service.yaml`
- Create: `apps/fj-presentation/ingress.yaml`

**Interfaces:**
- Consumes: GitHub archive URL for pinned compilers commit.
- Produces: Service `fj-presentation` on port 80 and host `fj.lab.mateuseap.com`.

- [ ] Create Deployment with `emptyDir`, curl initContainer, nginx container on 8080, non-root UID, read-only root filesystem, tmp mounts, and resources.
- [ ] Create Service mapping port 80 to named container port `http`.
- [ ] Create cert-manager/Traefik Ingress with TLS.
- [ ] Validate YAML with `kubectl apply --dry-run=client` when kubectl is available and parse all files with Ruby Psych otherwise.
- [ ] Verify rendered source archive contains `index.html` and `assets/tapl-fig19-3.png` using the same shell copy command as initContainer.

### Task 2: ArgoCD Registration and Delivery

**Files:**
- Create: `argocd/app-fj-presentation.yaml`

**Interfaces:**
- Consumes: `apps/fj-presentation` manifests.
- Produces: Auto-synced ArgoCD app in namespace `fj-presentation`.

- [ ] Add wave-2 Application using repo `mateuseap/homelab`, revision `main`, and CreateNamespace.
- [ ] Run repository manifest checks and inspect complete diff.
- [ ] Commit, push feature branch, PR to develop, merge, release develop to main.
- [ ] Observe ArgoCD/Kubernetes rollout, TLS, HTTP 200, assets, and presentation navigation.
- [ ] If live verification fails, inspect pod/init logs and ingress/certificate before changing manifests.
