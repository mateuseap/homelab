# ADR-006: Nightly Backups to Cloudflare R2

**Status:** Accepted  
**Date:** 2026-07-23

## Context

The cluster is single-node with node-local (local-path) storage. There is no replicated volume and no HA, so a lost or rebuilt node loses everything on disk. Application data (the ChessKernel PostgreSQL database) must survive node loss and be restorable onto a fresh cluster. The backup target should cost little to nothing and be reachable from inside the cluster with standard tooling.

Options: a cloud provider's managed backup, an S3-compatible object store, or copying dumps to another host. Cloudflare R2 was chosen for the object store because it is S3-compatible (so the standard `aws-cli` works unchanged) and has no egress fees, which matters for restores and drills.

## Decision

Run a **nightly `CronJob` that `pg_dump`s the database, gzips it, and uploads to Cloudflare R2** over the S3 API, with a **14-day rotation** (`apps/chesskernel/backup-cronjob.yaml`).

- Schedule `0 3 * * *` (03:00 UTC), `concurrencyPolicy: Forbid` so runs never overlap.
- The job runs a `postgres:16-alpine` container, installs `aws-cli`, dumps `chesskernel`, and copies `chesskernel-<date>.sql.gz` to `s3://<bucket>/chesskernel/` using the R2 endpoint.
- After upload it prunes: any dump whose key date is older than 14 days is deleted, so retention is bounded.
- R2 credentials (access key, secret, endpoint, bucket) come from the sealed secret `r2-backup-credentials` (see ADR-003).

Restore is a documented manual procedure (`gunzip | kubectl exec ... psql`) in the runbook.

## Consequences

- Data survives node loss: a rebuilt cluster is repopulated from git (manifests) plus the latest R2 dump. This is what makes the node disposable despite local-path storage.
- Backups are only trustworthy if restores are exercised. The runbook mandates a quarterly restore drill into a scratch database; a dump that has never been restored is not a backup.
- Retention is 14 days by key-date pruning. Older history is not kept; this is acceptable for a homelab and can be extended by changing the cutoff.
- The R2 token is a credential in the cluster. Because it transited an external channel during setup, rotating it is on the pending list in the security doc.
- Only PostgreSQL is backed up. Redis is a cache (regenerable), and Grafana/Prometheus data is observability history, not application data, so neither is included by design.
