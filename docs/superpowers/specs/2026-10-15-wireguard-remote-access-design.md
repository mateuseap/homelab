# WireGuard Remote Access Design

**Date:** 2026-10-15  
**Status:** Approved for implementation

## Purpose

Provide secure remote access from a MacBook Pro Early 2011 to the primary Omarchy workstation through a self-hosted WireGuard hub on the homelab VPS. Both clients initiate outbound tunnels to the VPS, so neither residential router needs an inbound port or public SSH/VNC exposure.

Completion requires the server configuration to be versioned, reviewed, merged through `develop` and `main`, deployed to the VPS, and verified live. Client-dependent checks must be reported separately until those devices connect.

## Observed Environment

The VPS was inspected before design:

- Ubuntu 24.04.4 LTS with Linux 6.8.0.
- WireGuard kernel module available.
- `wireguard-tools` not installed.
- k3s pod network `10.42.0.0/24` and service network `10.43.0.0/16`.
- Docker bridge `172.17.0.0/16`.
- IPv4 forwarding already enabled for k3s.
- `iptables-nft` with `netfilter-persistent`; `FORWARD` policy is `DROP`.
- Existing rules are managed by k3s, Flannel, Docker, and the host bootstrap.
- SSH uses keys only, root password login is disabled, and fail2ban is active.
- ArgoCD applications were synchronized and healthy.

The observed workstation LAN is `192.168.1.0/24`. The selected VPN subnet, `10.88.0.0/24`, does not overlap any observed host, cluster, Docker, or LAN subnet.

## Architecture Decision

Run WireGuard directly on the VPS host, managed by `wg-quick@wg0.service`.

Host installation is safer and smaller than a privileged container or Kubernetes pod:

- The kernel already provides WireGuard.
- No privileged container, host networking, image supply chain, or Kubernetes dependency is introduced.
- The VPN remains available when k3s is restarting or unavailable.
- systemd provides startup ordering, restart behavior, and boot persistence.
- Host firewall behavior remains explicit and inspectable.

ArgoCD cannot manage host packages, systemd units, `/etc/wireguard`, or host firewall persistence. The repository therefore manages an idempotent host bootstrap script and operational runbook. Running the versioned script is the narrow, technically necessary host-level deployment step.

## Addressing and Peer Model

| Device | Address | Role |
|---|---:|---|
| VPS | `10.88.0.1/24` | WireGuard hub |
| Primary Omarchy PC | `10.88.0.2/32` | SSH and desktop target |
| MacBook | `10.88.0.3/32` | Remote client |

The VPS listens on UDP port `51820` at its existing public IP. No additional DNS record is required because the public IP is stable and an IP endpoint avoids coupling tunnel recovery to DNS.

Each peer has an individual key pair. Private keys are generated and retained only on the corresponding device:

- VPS private key: `/etc/wireguard/server.key`, mode `0600`.
- Omarchy private key: local root-owned WireGuard configuration, mode `0600`.
- MacBook private key: local WireGuard configuration or NetworkManager secret store, depending on supported client platform.
- Only public keys are exchanged and stored in the server configuration.

No private key, preshared key, client configuration containing private material, token, or credential may enter Git history.

## Routing

This is a split tunnel. Only VPN addresses use WireGuard.

Server peer declarations use one host route per peer:

```ini
[Peer]
PublicKey = <OMARCHY_PUBLIC_KEY>
AllowedIPs = 10.88.0.2/32

[Peer]
PublicKey = <MACBOOK_PUBLIC_KEY>
AllowedIPs = 10.88.0.3/32
```

Client route declarations permit only the hub and the other authorized peer:

```ini
# Omarchy
AllowedIPs = 10.88.0.1/32, 10.88.0.3/32

# MacBook
AllowedIPs = 10.88.0.1/32, 10.88.0.2/32
```

Clients behind NAT use `PersistentKeepalive = 25`. The server does not need a keepalive because clients initiate traffic and refresh their endpoints.

No peer uses `0.0.0.0/0` or `::/0`. No WireGuard traffic is NATed or masqueraded. Normal internet traffic continues through each device's existing default route.

## Firewall Isolation

Deployment adds the minimum host rules:

1. Accept UDP destination port `51820` on the public interface so authenticated WireGuard handshakes can reach the kernel.
2. Accept established and related forwarded traffic for WireGuard.
3. Accept forwarding from `wg0` to `wg0`, allowing the two explicitly configured peers to communicate.
4. Drop new traffic entering through `wg0` when its output interface is not `wg0`.

These rules prevent VPN peers from reaching the VPS's LAN-like interfaces, pod network, service network, Docker bridge, or public internet through forwarding. Peer public keys and `/32` `AllowedIPs` prevent unregistered devices and source-address impersonation from joining the VPN.

The VPS itself remains reachable at `10.88.0.1` because host-destined traffic traverses `INPUT`, not `FORWARD`. Administrative access to the VPS over WireGuard is limited to services already listening on the host, primarily SSH. WireGuard cryptographic authentication is the first boundary and SSH public-key authentication remains the second boundary.

The deployment must not:

- Change the `INPUT`, `FORWARD`, or `OUTPUT` chain policies.
- Flush or replace any chain.
- Change port 22 or any SSH setting.
- Delete, reorder, or rewrite k3s, Flannel, Docker, node-exporter, or fail2ban rules.
- Add NAT, SNAT, DNAT, or masquerading.
- Expose client SSH or VNC publicly.

Rules are added idempotently with existence checks, labeled with stable comments, and persisted using the host's existing `netfilter-persistent` mechanism. Uninstall removes only rules bearing the WireGuard deployment's exact shape and comments.

## Configuration Lifecycle

The repository provides two focused host tools:

- `bootstrap/install-wireguard.sh`: installs `wireguard-tools`, creates the server key if absent, writes the base `wg0` configuration, installs sysctl and firewall rules, validates configuration, and enables `wg-quick@wg0`.
- `bootstrap/wireguard-peer.sh`: idempotently adds, updates, revokes, or renders a named peer using its public key and fixed address allocation.

The installer accepts client public keys through environment variables or explicit arguments. It never accepts or reads client private keys. Secrets are written using `umask 077`; diagnostic output never prints private keys.

Peer changes update `/etc/wireguard/wg0.conf` atomically, validate the candidate before replacement, apply runtime state through `wg syncconf`, and preserve service availability. Removing a peer deletes its public-key stanza and route, immediately revoking tunnel access.

The scripts operate on the VPS clone checked out at the released `main` revision. They must support repeated execution without duplicate rules, changed keys, service restarts, or unnecessary package operations.

## Safe Deployment and Rollback

Before deployment:

1. Validate shell syntax and automated safety tests.
2. Review the exact diff independently.
3. Keep the existing multiplexed SSH connection open.
4. capture existing WireGuard absence, firewall rules, routes, listeners, k3s health, and ArgoCD health.
5. Back up `/etc/iptables/rules.v4` and any pre-existing `/etc/wireguard` content with mode `0600`.

During deployment:

1. Install `wireguard-tools` without changing other packages.
2. Generate the server private key on the VPS.
3. Install configuration and firewall rules.
4. Start and enable `wg-quick@wg0`.
5. Open a second SSH connection before releasing the first.

Rollback disables `wg-quick@wg0`, removes only the WireGuard-specific rules, persists the resulting firewall, and leaves generated keys in the protected backup unless explicit key destruction is requested.

## Omarchy Client

The repository provides a public template and exact local installation instructions. The workstation is not modified remotely during this server task.

Expected client behavior:

- Install `wireguard-tools` from Arch repositories.
- Generate its key pair locally with mode `0600`.
- Configure `10.88.0.2/32`, endpoint `179.197.71.43:51820`, split routes, and `PersistentKeepalive = 25`.
- Enable `wg-quick@wg0` only after its public key is enrolled on the server.
- Preserve Omarchy's UFW defaults and permit SSH only on `wg0` or from `10.88.0.3` if an additional host rule is required.

No generic public SSH opening is allowed.

## WayVNC and SSH Tunnel

WayVNC binds only to loopback on the Omarchy workstation:

```ini
address=127.0.0.1
port=5900
```

The MacBook reaches it through SSH over WireGuard:

```bash
ssh -N -L 5900:127.0.0.1:5900 <user>@10.88.0.2
```

The VNC viewer connects to `127.0.0.1:5900`. This provides WireGuard encryption and authentication for network admission plus SSH encryption, host verification, and user authentication for desktop access. VNC itself never listens on the VPN or public interface.

WayVNC runs as a systemd user service bound to the active Hyprland session. Monitor selection is explicit for multi-monitor systems. Final commands and configuration keys must match the versions installed on the workstation at setup time.

Unattended graphical access requires an existing Hyprland graphical session. Automatic login is not enabled by this project because it weakens local physical security. Lock-screen capture and input behavior must be tested on the actual workstation before being documented as supported. SSH access remains available independently of the graphical session.

## MacBook Compatibility

The implementation must verify, from current primary sources, whether a maintained WireGuard client can run safely on macOS High Sierra 10.13. It must distinguish technical installability from acceptable security.

High Sierra itself no longer receives Apple security updates. If the official WireGuard client and a maintained userspace implementation do not support 10.13, the project will not recommend pinning an obsolete VPN build as a permanent remote-access solution.

Fallback order:

1. A supported maintained WireGuard implementation on the existing OS, only if verified.
2. A newer supported macOS through OpenCore Legacy Patcher, only if hardware acceleration and stability are acceptable on the specific Early 2011 model.
3. Linux on the MacBook, with WireGuard in the kernel and current security updates. Distribution choice must account for the machine's Broadcom Wi-Fi and GPU hardware.

The server architecture is client-independent and does not need redesign if the MacBook changes operating system.

## Repository Changes

Expected files:

```text
bootstrap/install-wireguard.sh
bootstrap/wireguard-peer.sh
tests/wireguard-host-test.sh
docs/adr/007-host-wireguard-hub.md
docs/operations/wireguard-remote-access.md
docs/examples/wireguard/omarchy.conf.example
docs/examples/wireguard/macbook.conf.example
docs/superpowers/plans/2026-10-15-wireguard-remote-access.md
docs/superpowers/specs/2026-10-15-wireguard-remote-access-design.md
```

Existing architecture, networking, security, runbook, bootstrap, and README documents are updated only where the new host service changes their claims or recovery procedure.

## Verification

### Before merge

- Shell syntax passes for every script.
- Static safety test confirms exact subnet, split routes, key permissions, idempotent rule checks, no full-tunnel route, and no NAT.
- `shellcheck` passes when available.
- No private key or placeholder resembling a real secret appears in the Git diff.
- Independent review finds no unresolved security or correctness issue.

### After release and deployment

- Released `main` commit is present in `/root/homelab`.
- `wg-quick@wg0` is enabled and active.
- `wg0` owns `10.88.0.1/24`.
- UDP `51820` is listening.
- `wg show` contains only enrolled public peers and never emits private material into logs or reports.
- Firewall contains one copy of each intended rule and all pre-existing rules remain.
- No WireGuard NAT rule exists.
- A second SSH connection succeeds.
- k3s node remains Ready.
- Every ArgoCD application remains synchronized and healthy.
- Re-running the installer produces no duplicate rules or unintended service changes.

### Deferred until clients connect

- WireGuard handshake age and byte counters for Omarchy and MacBook.
- Ping between `10.88.0.2` and `10.88.0.3`.
- SSH from MacBook to Omarchy over `10.88.0.2`.
- WayVNC through the SSH local-forward tunnel.
- Behavior across client reboot, NAT changes, workstation lock, monitor changes, and VPS reboot.

Reports must clearly separate server checks completed live from deferred client checks.

## Acceptance Criteria

1. WireGuard runs directly on the VPS host and starts automatically after reboot.
2. Only UDP `51820` is newly exposed publicly.
3. Only enrolled device public keys can join.
4. Omarchy and MacBook can communicate over dedicated `/32` addresses once configured.
5. No client uses the VPS as a default internet gateway or route to unrelated VPS networks.
6. Existing SSH, firewall, k3s, ArgoCD, applications, and administrative access remain healthy.
7. All private keys remain outside Git and use restrictive filesystem permissions.
8. Peer addition, key rotation, removal, revocation, diagnostics, and rollback are documented and reproducible.
9. WayVNC remains loopback-only and is accessed through SSH over WireGuard.
10. High Sierra compatibility guidance is evidence-based and does not recommend an unsupported client as secure.
11. Changes reach `develop`, then `main`, deploy to the VPS, and receive live verification before completion is claimed.
