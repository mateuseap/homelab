# Sotto: usage and operations guide

Bilingual English/Portuguese microphone transcription in the browser, with
AI-generated session summaries through 9Router. Server-side Deepgram streaming;
no audio is ever written to disk.

## Using it

1. Open https://sotto.lab.mateuseap.com
2. App shows a login page; enter the password. The app hashes it against a
   stored bcrypt hash and, on success, sets an `httpOnly` cookie that gates
   the session.
3. Grant microphone permission when prompted.
4. Choose English or Portuguese and start the session. Audio streams over
   WebSocket to the server, the server streams it to Deepgram, and the
   transcript comes back live.
5. End the session to request an AI-generated summary through 9Router, then
   close the tab or start another session.

Nothing is recorded or stored. Refreshing the page loses the transcript.

## Infra perspective

**Two pods, no database, no PVC.**

| Component | Image | CPU request | Memory | Notes |
|--|--|--|--|--|
| `client` | `ghcr.io/mateuseap/sotto-client` | 10m | 24-64Mi | nginx serving static bundle, proxies `/api` and the WebSocket upgrade to `server` |
| `server` | `ghcr.io/mateuseap/sotto-server` | 50m | 120-300Mi | holds the WebSocket + Deepgram streams |

**Session cap: `MAX_SESSIONS=5`.** Each open session is one live Deepgram
stream, i.e. real money and one held connection on a 1 vCPU node. The 6th
concurrent session gets rejected, not queued. This is the actual capacity
ceiling, not the auth gate, which only keeps strangers out.

**Deploy strategy is `Recreate`, not `RollingUpdate`,** on the server. A
rolling update would briefly run two server pods, doubling concurrent
Deepgram streams against the same key. Recreate means a deploy drops all
live sessions for a few seconds instead.

**Access control:** app-level login, not Traefik `BasicAuth`. The password
is hashed with bcrypt and stored (sealed) as `LOGIN_PASSWORD_HASH`; on
success the server sets an `httpOnly` cookie that gates the rest of the
session. Replaces the old `middleware.yaml` + `auth-secret.yaml` pair
and the baked-in `SESSION_TOKEN` flow.

**Secrets:** `deepgram-api-key`, the bcrypt hash `login-password-hash`, and
`summary-api-key` live in `apps/sotto/sealed-secrets.yaml`, sealed with the
cluster's public key. Rotating one means re-sealing with `kubeseal --raw --cert`
against the same field name (see `docs/RUNBOOK.md`) and replacing only that
ciphertext line, never the whole file. `SUMMARY_MODEL` selects the model used
through 9Router for session summaries.

**Cost model:** Deepgram bills per audio-minute streamed. Nothing transcribes
when no one is connected, so transcription idle cost is zero. Worst case is
5 concurrent sessions maxed out until someone notices the credit draining.
There is no transcription cache or free retry, every second of audio is a
paid second upstream. Summary requests use 9Router separately.

**Images are private** (GHCR), pulled via the `ghcr-pull` imagePullSecret
in both `client.yaml` and `server.yaml`. The repo itself is also private.

**No horizontal scaling.** `replicas: 1` on both pods; scaling out would
need session affinity or a shared session store, neither exists. If
`MAX_SESSIONS=5` becomes a real bottleneck, raise the env var and watch
memory before adding a second replica.

## Summary path

Sotto sends transcript text to the in-cluster 9Router-backed summary API using
`SUMMARY_API_KEY` and `SUMMARY_MODEL`. 9Router requires API-key authentication,
disables request logs, and persists OAuth tokens and issued API keys on its PVC.
Transcript audio remains on the live Deepgram stream and is never stored by
Sotto or 9Router.
