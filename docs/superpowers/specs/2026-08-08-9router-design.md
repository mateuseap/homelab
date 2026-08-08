# 9Router on homelab — Design

## Why

Claude Code sessions die on rate limits mid-work. [9Router](https://github.com/decolua/9router) is a self-hosted, OpenAI-compatible AI gateway that auto-falls-back across 40+ providers, including a caller's own subscription OAuth tokens (Claude Code, Codex, Copilot, Cursor). Running it on the homelab VPS gives a stable `https://9router.lab.mateuseap.com` endpoint the user's local Claude Code CLI can point at, so a 429 mid-session falls back instead of stopping work.

## Scope decisions (from brainstorming)

- **Provider scope:** include the user's own subscription OAuth tokens (Claude Code, etc.), not just free/no-auth providers. Accepted ToS/ban risk knowingly.
- **Primary goal:** fallback on rate limits, not cost optimization or multi-tool convenience.
- **Exposure:** standard pattern — public Ingress + TLS, gated by `REQUIRE_API_KEY` bearer auth only. No extra IP allowlisting.
- **Monitoring/backup:** out of scope for v1. No documented `/metrics` endpoint upstream. 9Router writes its own rotating backups under `DATA_DIR/db/backups`, which lives on the PVC — sufficient for v1.

## Security note (flagged to user, accepted)

9Router's OAuth-token-as-backend model uses subscription auth outside each vendor's official API surface — plausible ToS violation / account-flagging risk for Anthropic and other connected providers. The PVC holds live OAuth tokens, issued API keys, and usage history — it is the most sensitive volume on the cluster after chesskernel's Postgres. Cloud Sync (9Router's own telemetry/config-sync feature, default `CLOUD_URL=https://9router.com`) is left disabled — nothing opts in via the dashboard, so config/tokens stay on the node.

## Architecture

Follows the existing `apps/<name>/` + `argocd/app-<name>.yaml` GitOps pattern used by chesskernel/pixelhub/mixtape (see `docs/operations/adding-an-app.md`). Single Deployment + PVC, same shape as `mixtape`.

```
apps/9router/
  deployment.yaml       # Deployment + PVC
  service.yaml           # ClusterIP :80 -> :20128
  ingress.yaml            # 9router.lab.mateuseap.com, letsencrypt-prod
  sealed-secrets.yaml      # JWT_SECRET, INITIAL_PASSWORD, API_KEY_SECRET, MACHINE_ID_SALT
argocd/app-9router.yaml    # wave 2, mirrors app-mixtape.yaml
platform/config/namespaces.yaml   # + 9router namespace block
docs/examples/9router-secrets.example.yaml   # template, gitignored when filled
```

### Deployment

- Image: `decolua/9router:latest` (Docker Hub, third-party — **deviation** from the GHCR-built-by-CI convention every other app follows here, since 9Router isn't one of this user's own repos; no `:sha` pin available upstream, comment this in the manifest).
- `strategy: Recreate` — single-writer SQLite, same reasoning as `apps/chesskernel/redis.yaml`.
- Port `20128`.
- Env:
  | Var | Value | Why |
  |---|---|---|
  | `DATA_DIR` | `/data` | PVC mount |
  | `PORT` | `20128` | match container port |
  | `NODE_ENV` | `production` | |
  | `REQUIRE_API_KEY` | `true` | gate the public endpoint |
  | `AUTH_COOKIE_SECURE` | `true` | dashboard sits behind TLS at Traefik |
  | `ENABLE_REQUEST_LOGS` | `false` | avoid prompts/keys landing in pod logs |
  | `JWT_SECRET`, `INITIAL_PASSWORD`, `API_KEY_SECRET`, `MACHINE_ID_SALT` | from sealed Secret | required, random-generated |
- Resources: `requests: {cpu: 30m, memory: 100Mi}`, `limits: {memory: 250Mi}` — same ballpark as `mixtape` (comparable single-instance Node service).
- Readiness probe: verify 9Router's actual health path during implementation (not documented upstream); fall back to a TCP socket check on 20128 if none exists.
- PVC `9router-data`, 5Gi, `local-path` storage class, mounted at `/data`.

### Service

ClusterIP, `port: 80 -> targetPort: 20128`, `selector: {app: 9router}` — matches the `mixtape` service shape.

### Ingress

`ingressClassName: traefik`, host `9router.lab.mateuseap.com`, `cert-manager.io/cluster-issuer: letsencrypt-prod`, TLS secret `9router-tls`. No custom domain needed (lab-only, personal use).

### Sealed secret

`JWT_SECRET`, `INITIAL_PASSWORD`, `API_KEY_SECRET`, `MACHINE_ID_SALT` — random values generated at implementation time, sealed via `kubeseal` following the plaintext-in-`/tmp`-then-`shred` flow documented in `docs/operations/adding-an-app.md` step 3.

### ArgoCD Application

Wave 2 (after cert-manager/sealed-secrets/monitoring), `path: apps/9router`, `namespace: 9router`, `automated: {prune: true, selfHeal: true}`, `syncOptions: [CreateNamespace=true]` — copy of `argocd/app-mixtape.yaml`.

### Namespace registration

Add a block to `platform/config/namespaces.yaml`: `argocd.argoproj.io/sync-options: Prune=false`, `homelab.mateuseap.com/description` summarizing what it is and that it holds subscription OAuth tokens, `app.kubernetes.io/part-of: homelab` label — matches the existing five blocks.

## Data flow

1. Local Claude Code CLI (user's laptop) → `ANTHROPIC_BASE_URL=https://9router.lab.mateuseap.com` with a router-issued API key → Traefik (TLS termination, host routing) → 9Router Service → pod.
2. 9Router checks `REQUIRE_API_KEY`, looks up the caller's routing rules in SQLite (`/data/db/data.sqlite`), picks a backend provider (subscription OAuth token or configured API key), proxies the request, applies fallback if the primary 429s.
3. Dashboard access (initial setup, provider OAuth connections, key issuance) is the same Ingress host, gated by `INITIAL_PASSWORD` login + `AUTH_COOKIE_SECURE`.

## Error handling

- Primary provider 429/5xx → 9Router's own fallback chain handles it (this is the tool's core function, not something this deployment adds logic for).
- Pod crash/restart → `Recreate` strategy means a brief gap while the old pod terminates before the new one starts (single-writer SQLite tradeoff, same as redis/mixtape today).
- Cert not yet issued → standard cert-manager HTTP-01 flow, no special-casing needed since `*.lab.mateuseap.com` wildcard already resolves.

## Testing / validation

1. `argocd app sync 9router` (or wait for auto-sync after merge).
2. `kubectl -n 9router get pods` — Running.
3. `kubectl -n 9router get certificate` — `Ready: True`.
4. `curl -I https://9router.lab.mateuseap.com` — 200/dashboard reachable.
5. Log into dashboard with `INITIAL_PASSWORD`, connect one provider (start with Claude Code OAuth), issue a routing API key.
6. Point local Claude Code CLI at the router (`ANTHROPIC_BASE_URL` + issued key) and confirm a request round-trips.
7. Confirm Grafana/ArgoCD stay green — no CPU/memory pressure regression on the other three apps from the new pod.

## Out of scope (v1)

- Prometheus `/metrics` / Grafana panel (no documented endpoint upstream).
- Nightly R2 backup of 9Router's SQLite data (relies on the tool's own internal rotating backup on the PVC for now).
- IP allowlisting beyond bearer-key auth.
- Non-Claude-Code providers/connections (can be added later via the dashboard without touching this repo).
