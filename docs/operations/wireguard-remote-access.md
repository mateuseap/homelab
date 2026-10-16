# WireGuard Remote Access

This guide operates the host-level WireGuard hub described in [ADR-007](../adr/007-host-wireguard-hub.md). WireGuard connects the VPS (`10.88.0.1`), primary Omarchy workstation (`10.88.0.2`), and MacBook (`10.88.0.3`). It is a split tunnel. Normal internet traffic never traverses the VPS.

## Security model

- Each device generates and retains its own private key.
- Git contains scripts, public templates, and documentation only.
- Only UDP `51820` is added to the public VPS surface.
- Server peers have fixed `/32` addresses.
- Forwarding is permitted only from `wg0` back to `wg0`.
- No NAT or default route is configured.
- WayVNC listens on loopback and is reached through SSH over WireGuard.
- WireGuard authenticates the device; SSH independently authenticates the user and host.

Completed client configurations and key files are secrets. Store them outside this repository with mode `0600`. Never paste private keys into issues, pull requests, logs, shell history, or chat.

## Server deployment

Keep the current multiplexed SSH connection open throughout deployment.

### 1. Preflight and backup

```bash
cd /root/homelab
git status --short
git fetch origin
git merge-base --is-ancestor HEAD origin/main

install -d -m 700 /root/wireguard-preflight
iptables-save > /root/wireguard-preflight/iptables-before.rules
cp -a /etc/iptables/rules.v4 /root/wireguard-preflight/rules.v4.before
[ ! -e /etc/wireguard ] || cp -a /etc/wireguard /root/wireguard-preflight/wireguard.before
```

Stop if the clone is dirty or cannot fast-forward. These backup files contain security-sensitive host state and must remain mode `0600` under `/root`.

### 2. Update to released `main`

```bash
git checkout main
git pull --ff-only origin main
git rev-parse HEAD
```

Confirm the revision matches the merged release PR before continuing.

### 3. Install

```bash
sudo ./bootstrap/install-wireguard.sh
sudo ./bootstrap/install-wireguard.sh --check
```

The installer:

- installs `wireguard-tools` only when `wg` is absent;
- generates `/etc/wireguard/server.key` only when absent;
- creates `/etc/wireguard/wg0.conf` with mode `0600` only when absent;
- persists IPv4 forwarding;
- installs `wireguard-firewall.service`, which on every boot creates nftables table `inet homelab_wireguard` (forward hook, priority `-10`, before all k3s and Docker iptables chains) dropping traffic from `wg0` to any other interface, plus two labeled iptables accepts (UDP `51820` input, `wg0` to `wg0` forward);
- never runs `netfilter-persistent save`, so transient k3s, Flannel, and Docker chains are not snapshotted;
- enables and starts `wg-quick@wg0`;
- validates service, address, forwarding, and rules.

Print the server public key, never the private key:

```bash
sudo sh -c 'wg pubkey < /etc/wireguard/server.key'
```

Open a second SSH connection before closing the deployment connection:

```bash
ssh -o BatchMode=yes -i ~/.ssh/homelab_vps root@179.197.71.43 true
```

## Omarchy client

Install from Arch's official repositories:

```bash
sudo pacman -S wireguard-tools
sudo install -d -m 700 /etc/wireguard
sudo sh -c 'umask 077; wg genkey > /etc/wireguard/private.key'
sudo sh -c 'wg pubkey < /etc/wireguard/private.key > /etc/wireguard/public.key'
sudo cat /etc/wireguard/public.key
```

Copy `docs/examples/wireguard/omarchy.conf.example` to a temporary path outside Git. Replace `<PRIVATE_KEY>` with `/etc/wireguard/private.key` contents and `<SERVER_PUBLIC_KEY>` with the VPS public key, then install it:

```bash
sudo install -m 600 /path/outside/git/omarchy.conf /etc/wireguard/wg0.conf
sudo systemctl enable --now wg-quick@wg0
sudo wg show
```

Enroll the displayed Omarchy public key on the VPS first:

```bash
sudo /root/homelab/bootstrap/wireguard-peer.sh add omarchy '<OMARCHY_PUBLIC_KEY>'
```

### Omarchy firewall

Omarchy enables UFW with default-deny incoming. Permit SSH only from the MacBook VPN address on `wg0`:

```bash
sudo ufw allow in on wg0 proto tcp from 10.88.0.3 to 10.88.0.2 port 22 comment 'SSH from WireGuard MacBook'
sudo ufw status numbered
```

Do not add a generic public `22/tcp` allowance. If an existing SSH rule already provides broader access, review it separately rather than changing it as part of this setup.

## MacBook compatibility

### High Sierra is not a safe supported endpoint

The current official WireGuard app requires macOS 12.0 or later. The current `wireguard-go` source requires Go 1.23.1, while Go 1.20 was the last Go release supporting macOS 10.13. Homebrew classifies macOS 10.15 and earlier as unsupported without third-party patches. Current MacPorts ports exist, but no verified High Sierra build result establishes a maintained path.

Therefore stock macOS High Sierra is a blocker for a maintained native WireGuard endpoint. An old WireGuard build on an unpatched OS may be technically installable, but it is not recommended as secure remote access.

Primary references:

- [WireGuard App Store listing](https://apps.apple.com/us/app/wireguard/id1451685025)
- [`wireguard-go` module requirements](https://github.com/WireGuard/wireguard-go/blob/master/go.mod)
- [Go 1.20 release notes](https://go.dev/doc/go1.20)
- [Go 1.21 release notes](https://go.dev/doc/go1.21)
- [Homebrew support tiers](https://docs.brew.sh/Support-Tiers)
- [MacPorts wireguard-go](https://ports.macports.org/port/wireguard-go/)
- [MacPorts wireguard-tools](https://ports.macports.org/port/wireguard-tools/)

### Recommended path: Linux

Install a maintained Linux distribution, preferably Debian with Xfce or Fedora Xfce for low graphics demand. The Early 2011 model may require the proprietary Broadcom `wl` driver for BCM4331 Wi-Fi. Keep Ethernet or a supported USB Wi-Fi adapter available during installation. MacBookPro8,1 uses Intel HD 3000; MacBookPro8,2 and 8,3 also have TeraScale-era AMD graphics. Use `i915` for Intel and `radeon`, not `amdgpu`, for those AMD GPUs. Hyprland is not recommended on this hardware; Xfce offers a safer baseline.

On Linux, install WireGuard through the distribution package manager, generate keys locally, copy `docs/examples/wireguard/macbook.conf.example` outside Git, fill placeholders, and enroll only the public key:

```bash
sudo /root/homelab/bootstrap/wireguard-peer.sh add macbook '<MACBOOK_PUBLIC_KEY>'
```

### Alternative: OpenCore Legacy Patcher

OCLP documents Big Sur through Sequoia support for legacy Macs, but the 2011 models use non-Metal graphics requiring root patches. Metal-only applications and graphics behavior remain caveats. Test stability and graphics acceleration before treating this as the remote-access endpoint. Linux remains the simpler maintained option for this purpose.

References:

- [OCLP FAQ](https://dortania.github.io/OpenCore-Legacy-Patcher/FAQ.html)
- [OCLP Sequoia support notes](https://dortania.github.io/OpenCore-Legacy-Patcher/SEQUOIA-DROP.html)

## WayVNC through SSH

Arch packages WayVNC in the official Extra repository:

```bash
sudo pacman -S wayvnc
```

WayVNC v0.10.2 supports `wlr-screencopy` and `ext-image-copy-capture`; current Hyprland provides both protocols. Confirm compatibility with installed versions before relying on unattended access.

Create `~/.config/wayvnc/config` on Omarchy:

```ini
address=127.0.0.1
port=5900
enable_auth=false
```

No VNC authentication is acceptable here only because WayVNC is loopback-only and every connection must traverse authenticated SSH. This avoids legacy VNC authentication needed by old macOS Screen Sharing. Never change `address` to `0.0.0.0` or the VPN address.

Determine output and compositor socket inside Hyprland:

```bash
echo "$WAYLAND_DISPLAY"
wayvncctl output-list
```

Create `~/.config/systemd/user/wayvnc.service`, replacing `wayland-1` and `eDP-1` with observed values:

```ini
[Unit]
Description=Loopback-only WayVNC
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=WAYLAND_DISPLAY=wayland-1
ExecStart=/usr/bin/wayvnc --output=eDP-1 127.0.0.1 5900
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
```

Enable it from the active graphical session:

```bash
systemctl --user daemon-reload
systemctl --user enable --now wayvnc.service
systemctl --user status wayvnc.service
ss -ltn | grep '127.0.0.1:5900'
```

For all monitors, test `wayvnc --desktop` before changing the service. Without `--output`, WayVNC captures the first output.

From the MacBook or its replacement Linux installation:

```bash
ssh -N -L 5900:127.0.0.1:5900 <user>@10.88.0.2
```

Connect the VNC viewer to `127.0.0.1:5900`. High Sierra's built-in Screen Sharing is expected to work with no VNC authentication through this SSH tunnel, but this remains a client-dependent test.

WayVNC requires a running Wayland compositor session. It cannot present the display manager login screen. Automatic graphical login is intentionally not enabled because it weakens physical security. Hyprlock capture, virtual input, unlock, output changes, and reboot behavior must be tested on the actual workstation before unattended access is considered reliable.

## Peer lifecycle

### Inspect

```bash
sudo wg show wg0
sudo ./bootstrap/install-wireguard.sh --check
```

Never run `wg showconf wg0` in logs or reports because it includes the server private key.

### Rotate a client key

Generate a new key on the client, then atomically replace its server public key:

```bash
sudo ./bootstrap/wireguard-peer.sh add omarchy '<NEW_OMARCHY_PUBLIC_KEY>'
# or
sudo ./bootstrap/wireguard-peer.sh add macbook '<NEW_MACBOOK_PUBLIC_KEY>'
```

Replace the private key only on that client. Verify a handshake before securely deleting the old local private key.

### Revoke

```bash
sudo ./bootstrap/wireguard-peer.sh revoke omarchy
sudo ./bootstrap/wireguard-peer.sh revoke macbook
```

Revocation updates persistent and live state without restarting the interface or disturbing the other peer.

## Validation and diagnostics

Server checks:

```bash
sudo ./bootstrap/install-wireguard.sh --check
systemctl is-enabled wg-quick@wg0
systemctl is-active wg-quick@wg0
ip -brief address show wg0
ss -lunp | grep ':51820'
sudo wg show wg0
sudo iptables -S | grep homelab-wireguard
sudo nft list table inet homelab_wireguard
sudo iptables -t nat -S | grep -i wireguard && echo 'UNEXPECTED NAT RULE' || true
k3s kubectl get node
k3s kubectl -n argocd get applications
```

Client checks after enrollment:

```bash
sudo wg show
ping -c 3 10.88.0.1
# From MacBook only:
ssh <user>@10.88.0.2
```

Common failures:

- No handshake: verify endpoint, public keys, UDP `51820`, and system clocks.
- Handshake but no peer traffic: verify exact `/32` `AllowedIPs`, `ip_forward=1`, `homelab-wireguard` rules, and `wireguard-firewall.service`.
- Tunnel drops behind NAT: verify `PersistentKeepalive = 25` on each client.
- SSH refused: verify `sshd` on Omarchy and the UFW rule scoped to `wg0` and `10.88.0.3`.
- WayVNC unavailable: verify active Hyprland session, `WAYLAND_DISPLAY`, selected output, user service logs, and loopback listener.

## Rollback

Disable WireGuard and remove only its labeled firewall rules:

```bash
sudo ./bootstrap/install-wireguard.sh --uninstall
```

Keys and configuration are retained for recovery. Confirm SSH, k3s, and ArgoCD afterward. To restore pre-deployment firewall state only during incident recovery, inspect the saved rules first. Do not blindly restore an old full ruleset after k3s has changed its dynamic chains.

## VPS rebuild and key recovery

Back up `/etc/wireguard/server.key` out of band in a password manager or encrypted backup. Never store it in Git. After a rebuild, restore it as root with mode `0600` before running the installer. If no backup exists, let the installer generate a new key, obtain its public key, and update both client configurations. No client private key needs to move to the VPS.

## Verification boundary

Server installation is independently verifiable. These checks remain pending until clients are physically configured:

- Omarchy and MacBook handshakes.
- Inter-peer ping.
- SSH from MacBook to Omarchy.
- WayVNC through local SSH forwarding.
- Recovery after client reboot and NAT changes.
- Hyprlock and monitor-change behavior.
- Full VPS reboot persistence.

Record pending checks as pending, never as successful based only on configuration inspection.
