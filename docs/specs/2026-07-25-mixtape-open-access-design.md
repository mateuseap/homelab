# Mixtape: Open Access Addendum

**Date**: 2026-07-25 · **Status**: approved · **Supersedes**: the auth decision in [2026-07-25-mixtape-design.md](2026-07-25-mixtape-design.md)

## Goal

Drop the shared-password gate. Mixtape is a communal jukebox, not a private
archive: the point is that anyone with the link can browse, play, and add
tracks without memorizing a credential.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Auth | Removed entirely. `/api/tracks` has no middleware. | A password gate contradicts an "anyone can add music" jukebox |
| Secrets | `mixtape-secrets` SealedSecret removed; `SESSION_SECRET`/`PASSWORD_HASH` env vars removed from the Deployment | No longer read by the app, nothing to seal |
| Client UI | Rebuilt around an interactive Three.js device (drag-to-rotate, cream/serif hero, floating player bar, track carousel), inspired by the visual language of `thebuggeddev/vinyl`'s live demo, adapted for MP3s | The retro LCD-box UI from the original design was replaced alongside the auth removal; see the app repo's own README for the current experience |

## Resource budget

Unchanged from the original design; removing the secret and its two env vars
has no resource impact.

## Out of scope

Per-track ownership, moderation, or any access control. If abuse becomes a
problem, revisit; not addressed here.
