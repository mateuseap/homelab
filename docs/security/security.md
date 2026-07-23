# Security

This is a single-node homelab on a public VPS (1 vCPU / 4 GB, 179.197.71.43) with a public git repo. The security model follows from those two facts: secrets must be safe to commit, traffic must be encrypted end to end at the edge, and internal surfaces must not be exposed publicly. This document describes the model, the host hardening already applied, and the honest tradeoffs of running on one node.

## Secrets: the sealed-secrets model

All secrets live in git as `SealedSecret` custom resources, encrypted so the public repo is safe. See [ADR-003](../adr/003-sealed-secrets-for-public-repo.md) for why.

### The key

The sealed-secrets controller (`sealed-secrets-controller` in `kube-system`) holds an asymmetric key pair. The public half encrypts (used by `kubeseal` on your laptop), the private half decrypts (only in-cluster). A `SealedSecret` can only be decrypted by the controller that holds the matching private key, so committing it exposes nothing.

### Sealing a secret

```bash
cp docs/examples/<app>-secrets.example.yaml /tmp/secrets.yaml
# edit /tmp/secrets.yaml with real values
kubeseal --controller-namespace kube-system --format yaml \
  < /tmp/secrets.yaml > apps/<app>/sealed-secrets.yaml
shred -u /tmp/secrets.yaml
```

Plaintext secrets must never be committed. Only the sealed output goes into git; the plaintext is shredded immediately.

### Key backup

Sealed secrets are bound to the controller's key. A rebuilt cluster generates a new key and cannot decrypt the existing sealed secrets unless the old key is restored. Back the key up out of band and store it in a password manager, never in git:

```bash
kubectl -n kube-system get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealing-key-backup.yaml   # store OUTSIDE git
```

The sealing key was copied off the VPS and shredded on the host after the off-box backup was made.

### Rotation

To rotate the sealing key, let the controller generate a new key (it does so on a schedule, or force it), then re-seal every secret with the new public key and commit the results. To rotate an individual application secret, change its value in the plaintext template, re-seal, and commit. The old sealed value stops being valid once the new one is applied.

## TLS everywhere

Every public host is served over HTTPS with a Let's Encrypt certificate issued and renewed automatically by cert-manager over HTTP-01 (see [ADR-004](../adr/004-cert-manager-http01-vs-dns01.md)). TLS terminates once at Traefik; backends run plain HTTP inside the cluster, which is safe because the only inbound path is through the ingress. WebSocket and `wss` ride the same TLS path. Port 80 exists only for the ACME challenge and the HTTP-to-HTTPS redirect.

## Public vs cluster-internal surfaces

Only what has an `Ingress` with a `host:` rule is reachable from the internet. Everything else is cluster-internal and reachable only from inside the pod network.

- **Application `/metrics`** are served on the servers' cluster-internal Service ports and scraped by Prometheus through `ServiceMonitor`s. They are deliberately excluded from the public ingress: the client nginx proxies only the API paths (`/api`, `/socket.io`, `/colyseus`), never `/metrics`. LiveKit's Prometheus endpoint (6789) is cluster-internal the same way.
- **Databases and caches** (PostgreSQL, Redis) have `ClusterIP` Services with no Ingress and are never public.
- **LiveKit media ports** (7882/udp, 7881/tcp) are the documented exception that must be reachable from clients because WebRTC media cannot traverse Traefik (see the [networking doc](../networking.md)). Signaling still goes through the TLS ingress.

## Namespace isolation and Prune=false

Each workload lives in its own namespace (`chesskernel`, `pixelhub`, `monitoring`, `cert-manager`, `argocd`), which bounds blast radius and scopes RBAC. Every managed namespace carries `argocd.argoproj.io/sync-options: Prune=false` (`platform/config/namespaces.yaml`), so ArgoCD's automated prune can never delete a live namespace and everything in it, even if its declaration is removed. This is a deliberate guardrail against a destructive one-line change (see [ADR-002](../adr/002-argocd-app-of-apps-sync-waves.md)).

## Host hardening already applied

The following was applied directly on the VPS on 2026-07-23:

- **SSH is key-only.** Password authentication was enabled and the root password had been exposed, so `/etc/ssh/sshd_config.d/00-security-hardening.conf` now sets `PasswordAuthentication no`, `PermitRootLogin prohibit-password`, and `KbdInteractiveAuthentication no`. Key authentication was verified still working and password authentication confirmed disabled. (Was: HIGH. Fixed.)
- **node-exporter (9100) is firewalled to the pod network.** It had been exposed unauthenticated to the public internet, disclosing host CPU, memory, disk, and network metrics. Targeted iptables rules now ACCEPT from `10.42.0.0/16` (pods) and `127.0.0.0/8` and DROP everyone else, persisted with netfilter-persistent. External access was verified blocked and the Prometheus scrape verified still healthy (`up{job="node-exporter"} = 1`). (Was: MEDIUM. Fixed.)
- **fail2ban** is installed with an sshd jail (4 retries, 1 hour ban) as defense in depth.

## Pending items

- **Rotate the Cloudflare R2 token.** It transited an external channel during setup. Rotate it in the Cloudflare dashboard and re-seal `r2-backup-credentials`.
- **Rotate the old VPS root password.** It was exposed before SSH went key-only. Even with password login disabled, rotate it.

## Single-node tradeoffs (accepted)

On a single-NIC VPS the node IP equals the public IP, so the kubelet (10250) and the k3s API (6443) are reachable from the internet. Both are authenticated and return `401` without credentials, so this is a low-severity exposure, not an open door. Host-level blocking is risky here because the same interface carries the control plane, so blocking it wrong can lock out the cluster.

The recommended defense in depth is a **provider-level firewall** (the cloud panel), restricting 6443 and 10250 to known admin IPs while leaving 80, 443, and the LiveKit media ports open. This is the one meaningful hardening step left that does not risk the control plane, and it is the honest cost of running Kubernetes on one public node rather than a private control plane. There is no HA and no network policy engine beyond namespace isolation; both are conscious tradeoffs for a 1 vCPU homelab.
