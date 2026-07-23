# ADR-005: Wildcard DNS with Traefik SNI Host Routing

**Status:** Accepted  
**Date:** 2026-07-23

## Context

The platform hosts several services (ArgoCD, Grafana, both applications, LiveKit signaling) and will host more. Each needs a public URL. There is one node with one IP. The design goal is that adding a project requires no DNS change and no SSH: pushing manifests to git should be enough.

Two things had to be decided: how names map to the single IP, and how the node routes many hostnames arriving on the same ports 80 and 443.

## Decision

Use a **single wildcard DNS record** plus **Traefik host-based (SNI) routing**.

### Wildcard DNS

One record, `*.lab.mateuseap.com`, points at the node IP. Any new subdomain under `lab.mateuseap.com` resolves immediately with no further DNS change. ChessKernel's apex and `www` stay on their existing DNS pointing at the same node. Adding a project is a folder in `apps/` and an Application in `argocd/`, nothing more.

### Traefik SNI / host routing

Traefik (bundled with k3s) is the single ingress. Every service declares an `Ingress` with `ingressClassName: traefik` and a `host:` rule. Traefik terminates TLS, reads the SNI / `Host` header, and routes to the matching backend Service. All hosts share ports 80 and 443 on the node.

Current host map:

| Host | Backend |
|------|---------|
| `chesskernel.com`, `www.chesskernel.com` | ChessKernel client |
| `chesskernel.lab.mateuseap.com` | ChessKernel client |
| `pixelhub.lab.mateuseap.com` | PixelHub client |
| `argo.lab.mateuseap.com` | ArgoCD server |
| `grafana.lab.mateuseap.com` | Grafana |
| `livekit.lab.mateuseap.com` | LiveKit signaling (wss) |

## Consequences

- New services get a URL for free: the wildcard already resolves and Traefik routes by host, so no DNS edit and no SSH are needed.
- HTTP-01 certificate issuance still happens per host on first request (see ADR-004); the wildcard covers DNS resolution, not certificates.
- Traefik proxies HTTP, HTTPS, and WebSocket (including `wss`) by host. It cannot proxy arbitrary UDP, which is why LiveKit's WebRTC media uses node `hostPort`s instead of the ingress (see the networking doc). This is the one documented exception to "everything routes through Traefik by host."
- TLS terminates once, at Traefik. Backends such as ArgoCD run in insecure/plain HTTP mode inside the cluster (see ADR-002), which is safe because the only path in is through the ingress.
