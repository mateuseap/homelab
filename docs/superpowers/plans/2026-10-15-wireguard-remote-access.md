# WireGuard Remote Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a locked-down WireGuard hub on the VPS and provide reproducible, secret-safe client setup for Omarchy and the MacBook.

**Architecture:** WireGuard runs on the VPS host under `wg-quick@wg0`, outside Kubernetes because it is host connectivity needed even when k3s is unavailable. Versioned shell tools install the service and manage fixed `/32` peers, while explicit forwarding rules allow only peer-to-peer `wg0` traffic and block forwarding to every other interface.

**Tech Stack:** Bash, WireGuard kernel module and `wireguard-tools`, systemd, iptables-nft, GitHub Actions/GitFlow, SSH.

**Spec:** `docs/superpowers/specs/2026-10-15-wireguard-remote-access-design.md`

## Global Constraints

- Use `10.88.0.0/24`; VPS `10.88.0.1`, Omarchy `10.88.0.2`, MacBook `10.88.0.3`.
- Listen on UDP `51820` only.
- Never commit private keys, preshared keys, tokens, or real client configurations.
- Never add `0.0.0.0/0`, `::/0`, NAT, SNAT, DNAT, or `MASQUERADE` for WireGuard.
- Never change SSH configuration, firewall chain policies, or rules owned by k3s, Flannel, Docker, node-exporter, or fail2ban.
- Preserve existing administrative SSH access and validate a second SSH connection before releasing the deployment connection.
- Keep WayVNC bound to `127.0.0.1` and access it only through SSH over WireGuard.
- Follow topic branch to `develop`, release PR to `main`, deployment, live verification, then topic branch cleanup.
- Generated project text uses English and contains no em dash characters.

## Review Focus

- Re-running installation must not duplicate firewall rules, rotate keys, rewrite unchanged configuration, or unnecessarily restart WireGuard.
- Malformed or duplicate peer public keys and invalid peer actions must fail before changing the live server configuration.
- A peer must not route through the VPS to public, Kubernetes, Docker, or host networks.
- Package installation or service startup failure must leave SSH and existing firewall state intact and report a nonzero exit.
- Revocation must remove the peer from both persistent and live WireGuard state without disturbing the remaining peer.

---

### Task 1: Host Script Safety Contract

**Files:**
- Create: `tests/wireguard-host-test.sh`
- Create: `bootstrap/install-wireguard.sh`
- Create: `bootstrap/wireguard-peer.sh`

**Interfaces:**
- Consumes: Ubuntu 24.04 host with systemd, apt, iptables-nft, and nft.
- Produces: `install-wireguard.sh [--check|--uninstall]` and `wireguard-peer.sh <add|revoke|render> <omarchy|macbook> [public-key]`.

- [ ] **Step 1: Write the failing static and sandbox test**

Create an executable test that first requires both scripts, validates their shell syntax, rejects full-tunnel/NAT literals, and executes them against a temporary filesystem with command shims. Assert first install, second idempotent install, peer update, peer revocation, invalid key rejection, and uninstall behavior.

- [ ] **Step 2: Verify RED**

Run:

```bash
tests/wireguard-host-test.sh
```

Expected: `FAIL: install-wireguard.sh is not executable`.

- [ ] **Step 3: Implement minimal host installer**

Implement strict-mode Bash with:

```bash
WG_INTERFACE=wg0
WG_ADDRESS=10.88.0.1/24
WG_SUBNET=10.88.0.0/24
WG_PORT=51820
```

Use `umask 077`, apt only when `wg` is absent, atomic candidate files, `wg-quick strip` validation, comment-labeled `iptables -C` checks, a dedicated nftables isolation table applied by `wireguard-firewall.service` (never `netfilter-persistent save`), systemd enable/start, and a read-only `--check`. `--uninstall` removes only exact labeled rules and disables the interface without destroying keys.

- [ ] **Step 4: Implement minimal peer manager**

Maintain fixed identity/address mappings, validate WireGuard base64 public keys through `wg pubkey`, replace peer blocks atomically, validate before installation, and apply with `wg syncconf`. `render` emits public client templates without private material.

- [ ] **Step 5: Verify GREEN**

Run:

```bash
tests/wireguard-host-test.sh
```

Expected: `PASS: WireGuard host scripts satisfy safety and idempotency contract`.

- [ ] **Step 6: Run shell analysis**

Run:

```bash
bash -n bootstrap/install-wireguard.sh bootstrap/wireguard-peer.sh tests/wireguard-host-test.sh
command -v shellcheck >/dev/null && shellcheck bootstrap/install-wireguard.sh bootstrap/wireguard-peer.sh tests/wireguard-host-test.sh
```

Expected: no output or ShellCheck unavailable message recorded explicitly.

- [ ] **Step 7: Commit**

```bash
git add bootstrap/install-wireguard.sh bootstrap/wireguard-peer.sh tests/wireguard-host-test.sh
git commit -m "feat: add secure WireGuard host automation"
```

### Task 2: Public Client Templates and Operations Guide

**Files:**
- Create: `docs/examples/wireguard/omarchy.conf.example`
- Create: `docs/examples/wireguard/macbook.conf.example`
- Create: `docs/operations/wireguard-remote-access.md`
- Create: `docs/adr/007-host-wireguard-hub.md`
- Modify: `.gitignore`
- Modify: `README.md`
- Modify: `docs/networking.md`
- Modify: `docs/security/security.md`
- Modify: `docs/RUNBOOK.md`
- Test: `tests/wireguard-host-test.sh`

**Interfaces:**
- Consumes: host tools from Task 1 and compatibility research with source URLs.
- Produces: exact setup, enrollment, rotation, revocation, diagnostics, WayVNC tunnel, recovery, and rollback procedures.

- [ ] **Step 1: Extend test with documentation assertions**

Require both templates, exact split-route `AllowedIPs`, `PersistentKeepalive = 25`, loopback-only WayVNC settings, SSH local forwarding, secret file ignore patterns, no real private keys, and links from README/runbook/security/networking.

- [ ] **Step 2: Verify RED**

Run `tests/wireguard-host-test.sh`.

Expected: failure naming the first missing template or document.

- [ ] **Step 3: Add client templates**

Templates use `<PRIVATE_KEY>`, `<SERVER_PUBLIC_KEY>`, the fixed addresses, `179.197.71.43:51820`, split routes only, and keepalive 25. Each warns that completed files are secrets and must remain outside Git.

- [ ] **Step 4: Add ADR and runbook**

Document host-vs-container decision, subnet evidence, firewall isolation, server deployment, client key generation, peer enrollment, key rotation, revocation, diagnostics, rollback, VPS recovery, Omarchy UFW scoping, WayVNC systemd user setup, monitor selection, session limitations, and deferred tests.

- [ ] **Step 5: Add evidence-based MacBook guidance**

Cite primary sources for official WireGuard minimum macOS, MacPorts/Homebrew viability, High Sierra support status, and maintained alternatives. Clearly separate possible installation from supported and secure operation. Include Linux hardware caveats and OpenCore Legacy Patcher caveats only when sources support them.

- [ ] **Step 6: Update repository documentation**

Link guide and ADR, include UDP `51820` in network exposure map, explain host-level GitOps exception and secret handling, and add deployment/recovery commands to runbook.

- [ ] **Step 7: Verify GREEN and prose constraints**

Run:

```bash
tests/wireguard-host-test.sh
! grep -R $'—' README.md bootstrap docs tests
```

Expected: pass and no em dash matches.

- [ ] **Step 8: Commit**

```bash
git add .gitignore README.md docs tests/wireguard-host-test.sh
git commit -m "docs: add WireGuard client and operations guide"
```

### Task 3: Review and Local Verification

**Files:**
- Modify: files from Tasks 1 and 2 only when resolving valid findings.
- Create: durable review/checkpoint section in this plan or adjacent progress file if implementation state needs interruption recovery.

**Interfaces:**
- Consumes: complete implementation diff.
- Produces: reviewed branch with recorded verification evidence and exact deployment commands.

- [ ] **Step 1: Run complete local verification**

Run test, Bash syntax, ShellCheck when installed, secret-pattern scan, prohibited-route/NAT scan, and `git diff --check`.

- [ ] **Step 2: Request independent security/correctness review**

Review exact diff against the design, especially shell quoting, atomic replacement, firewall ordering, iptables persistence interactions, peer key validation, key leakage, and rollback.

- [ ] **Step 3: Resolve valid findings with TDD**

For each defect, add a failing case to `tests/wireguard-host-test.sh`, observe failure, make the smallest fix, and rerun the full suite.

- [ ] **Step 4: Commit fixes if needed**

Use a focused Conventional Commit such as:

```bash
git commit -am "fix: harden WireGuard host deployment"
```

### Task 4: GitFlow Integration

**Files:**
- No source changes unless required by review or CI.

**Interfaces:**
- Consumes: verified topic branch.
- Produces: merged topic PR on `develop`, release PR merged to `main`, with source PR links and `develop` preserved.

- [ ] **Step 1: Push topic branch**

```bash
git push -u origin feature/wireguard-remote-access
```

- [ ] **Step 2: Open assigned PR to develop**

Title:

```text
feat: add secure WireGuard remote access
```

Body:

```markdown
#### Changes made

- Add idempotent host-level WireGuard installation and peer lifecycle tools.
- Restrict forwarding to authenticated traffic between the two VPN peers without full-tunnel routing or NAT.
- Add client templates, WayVNC-over-SSH instructions, compatibility guidance, tests, and recovery documentation.
```

Assign `@me`.

- [ ] **Step 3: Verify checks and merge topic PR**

Do not bypass branch protections or failed required checks. Delete only the topic branch after release and live verification, not during this merge if it remains needed for traceability.

- [ ] **Step 4: Open assigned release PR from develop to main**

Use `release: add secure WireGuard remote access`, exact `#### Changes made` heading, and source topic PR link.

- [ ] **Step 5: Verify and merge release PR**

Run `gh pr merge <release-pr> --merge` without `--delete-branch`. Confirm `origin/develop` still exists after merge.

### Task 5: VPS Deployment and Live Verification

**Files:**
- Runtime only: `/etc/wireguard/*`, `/etc/sysctl.d/`, persistent iptables state, systemd enablement.
- Update: durable checkpoint with sanitized evidence.

**Interfaces:**
- Consumes: released `main`, existing multiplexed SSH access, Omarchy/MacBook public keys when available.
- Produces: active server hub and client templates ready for local private-key completion.

- [ ] **Step 1: Capture pre-deployment evidence and backup**

Using the existing SSH control connection, record sanitized checksums/counts for firewall state, listeners, routes, SSH, k3s, ArgoCD, and existing WireGuard paths. Back up persistent firewall state and any pre-existing WireGuard directory with mode `0600`.

- [ ] **Step 2: Update VPS clone to released main**

Verify clean clone, fetch, fast-forward only to `origin/main`, and confirm exact released commit. Stop on local changes or non-fast-forward state.

- [ ] **Step 3: Run installer**

Execute released `bootstrap/install-wireguard.sh`. Do not log the server private key.

- [ ] **Step 4: Enroll available client public keys**

If client public keys are unavailable, leave server with no client peers and document exact enrollment commands. Never generate client private keys on the VPS merely to satisfy deployment status.

- [ ] **Step 5: Verify server and access safety**

Check service enabled/active, `wg0` address, UDP listener, sanitized `wg show`, exact firewall rules, absence of NAT, second SSH connection, k3s Ready, and all ArgoCD applications Synced/Healthy.

- [ ] **Step 6: Verify idempotency**

Run installer again and confirm no duplicate rules, key rotation, or unintended restart/config drift.

- [ ] **Step 7: Record deferred checks**

Mark peer handshake, inter-peer ping, Omarchy SSH, WayVNC tunnel, client reboot/NAT transition, lock-screen behavior, and VPS reboot as pending until their prerequisites exist. Never report these as passed.

- [ ] **Step 8: Prune topic branch after release verification**

Delete only fully merged local and remote `feature/wireguard-remote-access`. Keep `develop` and `main`.

## Final Checkpoint

Record:

```text
CURRENT PHASE:
CURRENT TASK:
CURRENT BRANCH:
BASE BRANCH:
COMPLETED:
IN PROGRESS:
REMAINING:
FILES CHANGED:
RELEVANT COMMITS:
TESTS PASSED:
TESTS FAILED:
DECISIONS MADE:
OPEN RISKS:
BLOCKERS:
PR TO DEVELOP:
DEVELOP MERGE STATUS:
RELEASE PR:
MAIN RELEASE STATUS:
DEPLOYMENT STATE:
LIVE VERIFICATION STATE:
BRANCH CLEANUP STATUS:
EXACT NEXT ACTION:
```
