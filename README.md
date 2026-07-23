# homelab

Everything running on my VPS, declared in one repo. GitOps: push to `main`,
[ArgoCD](https://argo.lab.mateuseap.com) makes the cluster match.

```
GitHub (this repo) ──▶ ArgoCD ──▶ k3s (1 vCPU / 4GB VPS)
                                   ├─ chesskernel   chess.lab.mateuseap.com
                                   ├─ pixelhub      pixelhub.lab.mateuseap.com (soon)
                                   ├─ ArgoCD UI     argo.lab.mateuseap.com
                                   └─ Grafana       grafana.lab.mateuseap.com
```

## Layout

| Path | What |
|---|---|
| `bootstrap/` | `install.sh` — fresh VPS → full platform in one command |
| `argocd/` | One Application manifest per deployed thing (app-of-apps) |
| `platform/` | Cluster plumbing: TLS issuer, monitoring values, ArgoCD ingress |
| `apps/<name>/` | Per-project manifests — add a folder, push, it deploys |
| `docs/` | [RUNBOOK](docs/RUNBOOK.md) (operate/migrate/restore) + design specs |

## Reproduce on any machine

```bash
git clone https://github.com/mateuseap/homelab && cd homelab
sudo bash bootstrap/install.sh
# + DNS wildcard, secrets, data restore → docs/RUNBOOK.md (≈30 min total)
```

## Stack

k3s · ArgoCD · Traefik · cert-manager (Let's Encrypt) · sealed-secrets ·
kube-prometheus-stack (trimmed for 1 vCPU) · nightly pg_dump → Cloudflare R2
