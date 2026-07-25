# Mixtape: Design

**Date**: 2026-07-25 · **Status**: approved, current

## Goal

An open MP3 jukebox with an interactive 3D player, running on the homelab
node alongside ChessKernel and PixelHub, without adding another Postgres
instance to a 1 vCPU / 4GB node. Anyone with the link can browse, play, and
add tracks; there is no login.

The first version shipped with a shared-password gate. It was removed the
same day: a password contradicts the point of a communal jukebox anyone can
add to. The decisions below describe the current, shipped design.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Architecture | Single combined Node/Express service (serves the built Vite client + JSON API from one process) | One pod, one image, one PVC — cheapest option on an already-loaded node vs. ChessKernel/PixelHub's split client+server pattern |
| Metadata storage | `better-sqlite3` file on the app's PVC | Avoids a third Postgres StatefulSet for a handful of metadata columns |
| File storage | Uploaded MP3s on the same PVC (`/data/tracks/`) | No object storage integration needed at this scale |
| Tagging | `music-metadata` parses ID3 on upload; falls back to filename | Library needs title/artist without manual entry |
| Auth | None. Every route is open, no accounts, no session | It is a communal jukebox, not a private archive; a password gate would defeat the purpose |
| Streaming | Range-request-aware `/api/tracks/:id/stream` | Required for seek/scrub in the player |
| Frontend | Vanilla JS + Vite, no framework, Three.js for the device scene | Small surface area for the app shell; Three.js is the one deliberate exception, needed for the interactive 3D player |

## Naming

- Repo `mateuseap/mixtape`, image `ghcr.io/mateuseap/mixtape`
- Hostname `mixtape.lab.mateuseap.com`, namespace `mixtape`

## Resource budget

Single pod, sized like PixelHub's server: `requests: {cpu: 30m, memory: 100Mi}`,
`limits: {memory: 250Mi}`. No additional stateful workload beyond one PVC. No
secret to seal.

## Repos

- `mateuseap/homelab`: `apps/mixtape/`, `argocd/app-mixtape.yaml`, docs and
  landing updates (this repo)
- `mateuseap/mixtape`: app code + CI → GHCR, own README/CONTRIBUTING/CI
  following the ChessKernel/PixelHub pattern, develop → main, tagged releases

## Out of scope (v1)

Playlists, multi-user accounts, moderation or access control, transcoding/
format conversion beyond MP3, mobile app, offline/PWA support.

## Verification

`docker build` succeeds; `pnpm test` (server unit + integration, client unit)
passes; manual smoke test: upload an MP3 with no login step, see it in the
library with correct tags, play/seek/pause the 3D player, delete it; ArgoCD
shows `mixtape` Healthy/Synced; HTTPS resolves at `mixtape.lab.mateuseap.com`.
