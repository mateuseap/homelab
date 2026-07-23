# Homelab Platform — Design

**Date**: 2026-07-23 · **Status**: approved

## Goal

One VPS (1 vCPU / 4GB), multiple projects, fully reproducible from a single
git repo. Kubernetes is an explicit goal (learning/portfolio), not just a means.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Orchestrator | k3s | Full k8s API at ~600MB; includes Traefik, local-path storage |
| GitOps | ArgoCD (trimmed: no dex/notifications, single replicas) | Its UI *is* the live app dashboard the user wants |
| Monitoring | kube-prometheus-stack, trimmed (5d retention, alertmanager off) | Grafana = live metrics dashboard |
| TLS | cert-manager + Let's Encrypt HTTP-01 via Traefik | No DNS API tokens needed |
| Secrets | sealed-secrets | Encrypted in git; repo stays public-safe |
| Backups | Nightly CronJob pg_dump → Cloudflare R2, 14-day rotation | Services + data migration |
| Domains | `*.lab.mateuseap.com` wildcard → VPS; apex/www stay on GitHub Pages | One DNS record covers all future apps |
| Registry | GHCR, images built by GitHub Actions in each app repo | Free for public repos |

## Naming

- `chesskernel.lab.mateuseap.com` (+ chesskernel's own domain, same ingress)
- `gather` → **pixelhub** at `pixelhub.lab.mateuseap.com` (future)
- `argo.lab.mateuseap.com`, `grafana.lab.mateuseap.com`

## Resource budget

k3s ~600MB · ArgoCD ~450MB · monitoring ~500MB · chesskernel ~450MB ·
pixelhub ~300MB (later) → ~1.5GB headroom. CPU is the scarce resource; all
platform components carry requests/limits.

## Repos

- `mateuseap/homelab` — this repo: bootstrap, platform, apps (source of truth)
- `mateuseap/chesskernel` — app code + CI → GHCR
- `mateuseap/pixelhub` — Gather.town-style world (own design cycle; v1 = 2D
  world + proximity text/audio via Phaser + Colyseus + LiveKit, audio-only
  because video would saturate 1 vCPU)

## Out of scope (v1)

argocd-image-updater (manual rollout restart for now) · video calls in
pixelhub · HA anything (single node by definition).

## Verification

Bootstrap re-runnable; smoke checks = all apps green, HTTPS on every host,
chesskernel login+game; quarterly backup-restore drill (RUNBOOK).
