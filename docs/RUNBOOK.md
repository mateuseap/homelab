# Runbook

Operational procedures. Everything here assumes SSH access to the VPS and
`kubectl` = `k3s kubectl` (alias it: `alias kubectl='k3s kubectl'`).

## Bootstrap a fresh machine (or migrate)

1. **DNS**: point `*.lab.mateuseap.com` (A record, wildcard) at the new VPS IP.
   Also point chesskernel's own domain at it.
2. **Bootstrap**:
   ```bash
   git clone https://github.com/mateuseap/homelab && cd homelab
   sudo bash bootstrap/install.sh
   ```
3. **Secrets** (first boot of a new cluster only — sealed secrets are bound to
   the cluster's key): re-seal and commit, see § Secrets below.
4. **Watch it converge**: `https://argo.lab.mateuseap.com` — all apps green.
   (Initial admin password: see install.sh output.)
5. **Restore data**: § Restore below.

Target: under 30 minutes end to end.

## Secrets (sealed-secrets)

Install the CLI once on your laptop: `brew install kubeseal` /
[releases](https://github.com/bitnami-labs/sealed-secrets/releases).

```bash
cp apps/chesskernel/secrets.example.yaml /tmp/secrets.yaml
# edit /tmp/secrets.yaml with real values
kubeseal --controller-namespace kube-system --format yaml \
  < /tmp/secrets.yaml > apps/chesskernel/sealed-secrets.yaml
git add apps/chesskernel/sealed-secrets.yaml && git commit -m "chore: seal secrets" && git push
shred -u /tmp/secrets.yaml
```

**Back up the sealing key** (lets you reuse sealed secrets on a rebuilt cluster):

```bash
kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealing-key-backup.yaml   # store OUTSIDE git (password manager)
```

## Restore a database backup

```bash
# list available dumps
aws s3 ls s3://homelab-backups/chesskernel/ --endpoint-url $R2_ENDPOINT
# download + restore into the running cluster
aws s3 cp s3://homelab-backups/chesskernel/chesskernel-YYYY-MM-DD.sql.gz . \
  --endpoint-url $R2_ENDPOINT
gunzip -c chesskernel-YYYY-MM-DD.sql.gz | \
  kubectl -n chesskernel exec -i statefulset/postgres -- \
    psql -U chesskernel chesskernel
```

**Quarterly drill**: restore the latest dump into a scratch database
(`createdb scratch && psql scratch < dump`) and sanity-check row counts.
A backup that has never been restored is not a backup.

## Deploy a new version of an app

CI pushes `:latest` to GHCR on merge to main. Then:

```bash
kubectl -n chesskernel rollout restart deploy/server deploy/client
```

(Automating this with argocd-image-updater is a later milestone.)

## Add a new project

1. Create `apps/<name>/` with Deployment/Service/Ingress (+ sealed secrets).
2. Add `argocd/app-<name>.yaml` (copy `app-chesskernel.yaml`, change name/path).
3. Push. ArgoCD picks it up; cert-manager issues TLS for its subdomain. Done —
   no DNS change needed (wildcard covers it), no SSH needed.

## Cutover from docker-compose (one-time, chesskernel)

1. Dump the live DB: `docker exec chesskernel_postgres pg_dump -U chesskernel chesskernel | gzip > pre-k3s.sql.gz`
2. `docker compose -f docker/docker-compose.prod.yml down` (frees ports 80/443)
3. Run bootstrap (§ above), seal secrets, wait for green.
4. Restore `pre-k3s.sql.gz` (§ Restore).
5. Verify: login + play a game on both domains, HTTPS valid.
6. Rollback if needed: `docker compose up -d` brings the old stack back.

## Troubleshooting quickies

| Symptom | Check |
|---|---|
| App red in ArgoCD | `kubectl -n <ns> describe pod ...` — usually missing sealed secret |
| No TLS cert | `kubectl describe certificate -A` — DNS must already resolve for HTTP-01 |
| Node pressure | Grafana → Node Exporter dashboard; CPU throttling shows here first |
| ArgoCD UI slow | It shares 1 vCPU with everything — normal during syncs |
