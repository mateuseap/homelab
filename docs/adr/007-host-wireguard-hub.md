# ADR-007: Host WireGuard Hub

**Status:** Accepted

**Date:** 2026-10-15

## Context

Remote access must connect an Omarchy workstation and a MacBook through the public VPS without opening residential router ports or exposing either client's SSH or VNC service publicly. The tunnel must remain useful when k3s is unavailable, must not carry ordinary internet traffic, and must preserve the VPS's existing k3s, Docker, SSH, and firewall behavior.

The inspected VPS uses Ubuntu 24.04, includes the WireGuard kernel module, and does not have `wireguard-tools` installed. Existing networks are k3s pods at `10.42.0.0/24`, k3s services at `10.43.0.0/16`, and Docker at `172.17.0.0/16`. The observed workstation LAN is `192.168.1.0/24`.

## Decision

Run WireGuard directly on the VPS host as `wg-quick@wg0`, listening on UDP `51820`, with dedicated subnet `10.88.0.0/24`:

- VPS: `10.88.0.1`
- Omarchy: `10.88.0.2`
- MacBook: `10.88.0.3`

Use `/32` peer routes and client split routes only. Do not add NAT or a default route through the VPS. Allow forwarded traffic only when both ingress and egress interfaces are `wg0`; drop traffic entering `wg0` that would leave through another interface.

Manage host state with versioned, idempotent scripts because ArgoCD cannot manage host packages, systemd units, `/etc/wireguard`, or persistent host firewall rules. Private keys remain on their respective hosts and never enter Git.

## Alternatives

### Privileged container

Rejected. It adds image supply-chain exposure, `NET_ADMIN`, host networking, volume mounts, and runtime dependency while firewall and kernel state still belong to the host.

### Privileged Kubernetes pod

Rejected. Remote administrative connectivity should not depend on k3s health. It would also require broad host privileges and complicate boot ordering.

### Tailscale, ZeroTier, or commercial VPN

Rejected by requirement. Coordination and cryptographic identity remain self-hosted with native WireGuard.

## Consequences

- VPN remains available independently of k3s.
- One UDP port is added to the VPS public surface.
- Host deployment is a documented GitOps exception: source and desired behavior live in Git, while a released script applies host state through SSH.
- The VPS is not a full-tunnel gateway and cannot relay peer traffic into Kubernetes, Docker, or public networks.
- Rebuilding the VPS requires restoring the server private key from an out-of-band backup or enrolling a newly generated server public key on both clients.
- Client private keys cannot be restored from this repository and must be backed up securely per device.

See [WireGuard Remote Access](../operations/wireguard-remote-access.md) for deployment and operation.
