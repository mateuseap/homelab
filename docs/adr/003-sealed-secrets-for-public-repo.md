# ADR-003: Sealed-Secrets for Public-Repo-Safe Secrets

**Status:** Accepted  
**Date:** 2026-07-23

## Context

This repository is public, and being public is a goal: it is a portfolio piece and a reference others can read. GitOps also requires that everything the cluster needs live in git, including secrets (database passwords, JWT signing key, Redis password, LiveKit API keys, and the Cloudflare R2 backup credentials). Plain Kubernetes `Secret` objects are only base64-encoded, not encrypted, so committing them to a public repo would expose them.

The options considered were an external secret manager (Vault, cloud KMS, SOPS with a cloud key), an out-of-band secret bootstrap (secrets applied by hand, never committed), and sealed-secrets.

## Decision

Use **Bitnami sealed-secrets**.

- A controller in the cluster (`sealed-secrets-controller` in `kube-system`) holds an asymmetric key pair. The public half encrypts, the private half decrypts.
- The `kubeseal` CLI encrypts a plain `Secret` into a `SealedSecret` custom resource that only this cluster's controller can decrypt. The encrypted resource is safe to commit to a public repo.
- ArgoCD applies the `SealedSecret`; the controller decrypts it in-cluster into a real `Secret` that pods mount as usual.
- No external service, no cloud dependency, no monthly cost. The trust anchor is a single key that stays in the cluster.

The sealed secrets live in `apps/chesskernel/sealed-secrets.yaml` and `apps/pixelhub/sealed-secrets.yaml`. Plaintext templates live in `docs/examples/` with placeholder values only.

## Consequences

- Sealed secrets are bound to the controller's key. A rebuilt cluster generates a new key, so the existing sealed secrets cannot be decrypted unless the key is restored. The sealing key must be backed up out of band (password manager), never committed. See the security doc for the backup, restore, and rotation procedure.
- Sealing is a manual step in the workflow: edit a plaintext template in `/tmp`, run `kubeseal`, commit the result, then shred the plaintext. Plaintext secrets must never be committed.
- The R2 backup credentials are sealed the same way (`r2-backup-credentials`). Because the R2 token transited an external channel during setup, it is on the pending-rotation list in the security doc.
- Because the sealed-secrets controller is a wave-0 dependency, application pods that mount its output do not start until decryption succeeds (see ADR-002).
