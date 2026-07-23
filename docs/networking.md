# Networking

One node, one IP, many hostnames. This document describes how names reach the node, how the node routes them, how certificates are issued, and the single exception to host-based routing (LiveKit media). For the decisions behind it, see [ADR-005](adr/005-wildcard-dns-traefik-sni-routing.md) and [ADR-004](adr/004-cert-manager-http01-vs-dns01.md).

## Wildcard DNS

A single wildcard A record, `*.lab.mateuseap.com`, points at the node IP. Any subdomain under `lab.mateuseap.com` resolves to the node with no further DNS change, so adding a service never touches DNS. ChessKernel's apex and `www` point at the same node with their own records.

## Traefik ingress and SNI host routing

Traefik ships with k3s and is the single ingress controller. Every service declares an `Ingress` with `ingressClassName: traefik` and a `host:` rule. Ports 80 and 443 are shared by all hosts; Traefik terminates TLS, reads the SNI / `Host` header, and routes to the matching backend Service. HTTP, HTTPS, and WebSocket (`wss`) all route this way.

```mermaid
flowchart LR
    DNS["*.lab.mateuseap.com<br/>chesskernel.com"] --> Node["node :80 / :443"]
    Node --> Traefik["Traefik<br/>TLS termination + host routing"]
    Traefik -->|chesskernel.com, chesskernel.lab| CK["chesskernel client"]
    Traefik -->|pixelhub.lab| PH["pixelhub client"]
    Traefik -->|argo.lab| ARG["argocd-server"]
    Traefik -->|grafana.lab| GRAF["grafana"]
    Traefik -->|livekit.lab| LK["livekit :7880 (wss)"]
```

## Hostname map

| Host | Backend | Notes |
|------|---------|-------|
| `chesskernel.com` | ChessKernel client | Production domain; own Ingress + cert (`chesskernel-own-tls`) |
| `www.chesskernel.com` | ChessKernel client | Shares the production Ingress |
| `chesskernel.lab.mateuseap.com` | ChessKernel client | Separate Ingress + cert (`chesskernel-lab-tls`) |
| `pixelhub.lab.mateuseap.com` | PixelHub client | `pixelhub-tls` |
| `argo.lab.mateuseap.com` | ArgoCD server | TLS at Traefik; ArgoCD runs insecure internally |
| `grafana.lab.mateuseap.com` | Grafana | Ingress defined in the monitoring chart values |
| `livekit.lab.mateuseap.com` | LiveKit signaling | `wss` signaling only; media bypasses Traefik (see below) |

### Why ChessKernel has two Ingress objects

Traefik drops an Ingress's entire TLS configuration if any referenced certificate Secret is missing. Before the `*.lab.mateuseap.com` wildcard existed, the lab host could not pass HTTP-01, so its certificate could not issue. Splitting the production domain and the lab host into two separate Ingress objects means a pending lab certificate never takes down TLS for `chesskernel.com`. This is the general pattern to follow whenever one host resolves and another does not yet.

## cert-manager

A single `ClusterIssuer`, `letsencrypt-prod`, solves ACME HTTP-01 through Traefik (`platform/config/cluster-issuer.yaml`). Each Ingress requests a certificate with the `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation and a `tls:` block naming the Secret to store it in. Certificates are per host and issue on first request once the host resolves; the wildcard record covers resolution, not certificates. No DNS provider token is used. See [ADR-004](adr/004-cert-manager-http01-vs-dns01.md).

## The LiveKit media exception

Traefik proxies HTTP, HTTPS, and WebSocket by host, but it cannot proxy arbitrary UDP. LiveKit's WebRTC media therefore does not go through the ingress. Only the signaling channel (`wss` on `livekit.lab.mateuseap.com`, port 7880) uses Traefik; media uses node `hostPort`s directly (`apps/pixelhub/livekit.yaml`):

| Port | Protocol | Purpose | Path |
|------|----------|---------|------|
| 7880 | TCP (wss) | Signaling | Through Traefik ingress (`livekit.lab.mateuseap.com`) |
| 7882 | UDP | WebRTC media (single mux port) | `hostPort` directly on the node |
| 7881 | TCP | WebRTC media TCP fallback | `hostPort` directly on the node |
| 6789 | TCP | Prometheus metrics | Cluster-internal only, scraped by ServiceMonitor |

Because the LiveKit pod binds host ports, only one replica can run, so its Deployment uses `strategy: Recreate` and `enableServiceLinks: false` (the injected `LIVEKIT_PORT` service-link env would otherwise crash the server). `use_external_ip: true` makes LiveKit advertise the node's public IP for media.

A new or migrated node must allow `7882/udp` and `7881/tcp` in any provider-level firewall, alongside 80 and 443. See the [security doc](security/security.md) for the recommended firewall posture.
