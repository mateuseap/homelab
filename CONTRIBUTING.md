# Contributing to HomeLab

This repo is the single source of truth for a live single-node cluster. ArgoCD watches `main` with automated prune and self-heal, so a merge to `main` changes the running platform within a minute or two. Contribute accordingly.

## Golden rules

- **A merge to `main` deploys.** ArgoCD auto-syncs every Application. There is no separate deploy step and no staging cluster. Treat `main` as production.
- **Never commit plaintext secrets.** Seal them first (see below). The repo is public.
- **Change one thing at a time.** Then confirm the affected app returns green in ArgoCD and healthy in Grafana before moving on.
- **English only, and no em dash characters** anywhere in docs or manifests.

## Workflow

1. Branch from `main`:
   ```bash
   git checkout main && git pull
   git checkout -b feat/<short-name>   # or fix/, docs/, chore/
   ```
2. Make the change. Keep manifests small and one concern per file (match the existing `apps/` and `platform/` layout). Set resource `requests` and `limits` on every container; the node is 1 vCPU / 4 GB.
3. Validate locally where possible:
   ```bash
   kubectl apply --dry-run=client -f <changed-file>   # schema sanity
   ```
4. Commit using [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`).
5. Push and open a PR:
   ```bash
   git push -u origin feat/<short-name>
   gh pr create --assignee mateuseap
   ```
   Every PR is assigned to `mateuseap`. Do not merge without review; a merge deploys.

## Secrets: always seal

Plaintext secrets must never enter git. Use the sealed-secrets flow:

```bash
cp docs/examples/<app>-secrets.example.yaml /tmp/secrets.yaml
# edit /tmp/secrets.yaml with real values
kubeseal --controller-namespace kube-system --format yaml \
  < /tmp/secrets.yaml > apps/<app>/sealed-secrets.yaml
shred -u /tmp/secrets.yaml
```

Only the `SealedSecret` output is committed. See the [security doc](docs/security/security.md) and [ADR-003](docs/adr/003-sealed-secrets-for-public-repo.md) for the key, backup, and rotation model.

## What changes where

| You want to | Edit |
|-------------|------|
| Add a project | `apps/<name>/` + `argocd/app-<name>.yaml` (see [adding an app](docs/operations/adding-an-app.md)) |
| Change cluster plumbing (issuer, ingress, namespaces) | `platform/config/` |
| Tune monitoring | `platform/monitoring/values.yaml` |
| Edit the dashboard | `platform/config/grafana-dashboard-homelab.yaml` |
| Upgrade a Helm component | bump `targetRevision` in `argocd/platform-*.yaml` |
| Change bootstrap | `bootstrap/install.sh` (re-runnable and idempotent) |

## Reporting security issues

Do not open a public issue for a security vulnerability. Email `mateuseap@mateuseap.com` with details.

## License

By contributing you agree your contributions are licensed under the [MIT License](LICENSE).
