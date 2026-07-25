# Mixtape: Design

**Date**: 2026-07-25 · **Status**: approved

## Goal

A personal, password-gated MP3 library with a retro MP3/iPod-style player UI,
running on the homelab node alongside ChessKernel and PixelHub, without
adding another Postgres instance to a 1 vCPU / 4GB node.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Architecture | Single combined Node/Express service (serves built Vite SPA + JSON API from one process) | One pod, one image, one PVC — cheapest option on an already-loaded node vs. ChessKernel/PixelHub's split client+server pattern |
| Metadata storage | `better-sqlite3` file on the app's PVC | Avoids a third Postgres StatefulSet for a handful of metadata columns |
| File storage | Uploaded MP3s on the same PVC (`/data/tracks/`) | No object storage integration needed at this scale |
| Tagging | `music-metadata` parses ID3 on upload; falls back to filename | Library needs title/artist without manual entry |
| Auth | Single shared password (sealed secret, bcrypt-hashed) → signed httpOnly session cookie, gates browse + upload | Personal media, not a public app; no need for user accounts |
| Streaming | Range-request-aware `/api/tracks/:id/stream` | Required for seek/scrub in the player |
| Frontend | Vanilla JS + Vite, no framework | Small surface area; matches the app's scope |

## Naming

- Repo `mateuseap/mixtape`, image `ghcr.io/mateuseap/mixtape`
- Hostname `mixtape.lab.mateuseap.com`, namespace `mixtape`

## Resource budget

Single pod, sized like PixelHub's server: `requests: {cpu: 30m, memory: 100Mi}`,
`limits: {memory: 250Mi}`. No additional stateful workload beyond one PVC.

## Repos

- `mateuseap/homelab`: `apps/mixtape/`, `argocd/app-mixtape.yaml`, docs and
  landing updates (this repo)
- `mateuseap/mixtape`: app code + CI → GHCR, own README/CONTRIBUTING/CI
  following the ChessKernel pattern, develop → main, tagged releases

## Out of scope (v1)

Playlists, multi-user accounts, transcoding/format conversion beyond MP3,
mobile app, offline/PWA support.

## Verification

`docker build` succeeds; `pnpm test` (server unit + integration, client unit)
passes 80%+ coverage; manual smoke test: login, upload an MP3, see it in the
library with correct tags, play/seek/pause, delete it; ArgoCD shows `mixtape`
Healthy/Synced; HTTPS resolves at `mixtape.lab.mateuseap.com`.
