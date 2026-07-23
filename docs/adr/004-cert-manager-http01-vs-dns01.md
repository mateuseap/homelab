# ADR-004: cert-manager with HTTP-01 over DNS-01

**Status:** Accepted  
**Date:** 2026-07-23

## Context

Every public hostname needs a valid TLS certificate, issued and renewed automatically, at no cost. cert-manager with Let's Encrypt is the obvious tool. The open question is the ACME challenge type used to prove domain control: HTTP-01 or DNS-01.

- **HTTP-01** proves control by serving a token at `http://<host>/.well-known/acme-challenge/...`. It needs the host to already resolve to the cluster and port 80 to be reachable, but it needs no DNS provider API access.
- **DNS-01** proves control by creating a `_acme-challenge` TXT record. It supports wildcard certificates and does not need inbound port 80, but it requires an API token for the DNS provider, which is another secret to store, scope, and rotate.

## Decision

Use **cert-manager with a single `ClusterIssuer` (`letsencrypt-prod`) solving HTTP-01 through Traefik** (`platform/config/cluster-issuer.yaml`).

```yaml
solvers:
  - http01:
      ingress:
        class: traefik
```

- No DNS provider token is needed, so there is one fewer secret in the cluster and one fewer credential to rotate.
- It works with any DNS provider, since the only requirement is an A record pointing at the node.
- One certificate is issued per hostname. The wildcard DNS record (see ADR-005) routes traffic; it does not require a wildcard certificate.

## Consequences

- A hostname must already resolve to the node before its certificate can issue, because HTTP-01 validates over the live host. This is why ChessKernel uses two separate Ingress objects: the production domain (`chesskernel.com`) can issue immediately, while the lab host (`chesskernel.lab.mateuseap.com`) waits on the wildcard DNS record. Traefik drops an Ingress's entire TLS config if any referenced secret is missing, so keeping them separate stops the production cert from waiting on the lab cert.
- Certificates are per-host, not wildcard. Each new subdomain triggers its own issuance on first request, which is automatic and needs no manual step.
- Port 80 must stay reachable for the challenge and for the HTTP-to-HTTPS redirect. If HTTP-01 ever became insufficient (for example a need for wildcard certificates), the migration is to add a DNS-01 solver with a provider token; the `ClusterIssuer` is the only object that changes.
- cert-manager is a wave-0 dependency because its CRDs and the `ClusterIssuer` must exist before any Ingress requests a certificate (see ADR-002).
