# Adding an App

Everything the cluster runs is declared in this repo. Adding a project means writing manifests, sealing its secrets, and pushing. ArgoCD picks it up, cert-manager issues its TLS, and the wildcard DNS already resolves its host. No SSH and no DNS change are needed.

This guide uses `<name>` for the new project. ChessKernel and PixelHub in `apps/` are the two worked examples to copy from.

## 1. Application manifests in `apps/<name>/`

Create `apps/<name>/` with the Kubernetes objects the project needs. Keep them small and one concern per file, matching the existing layout.

A typical web app has:

- **`client.yaml`**: a Deployment (nginx serving the static bundle) plus a Service on port 80. The client nginx proxies its API path to the in-cluster `server` Service.
- **`server.yaml`**: a Deployment for the API plus a Service, and usually a ServiceMonitor (see step 5). Name the Service `server` so the client's nginx proxy target (`http://server:<port>`) resolves.
- **`ingress.yaml`**: the public route (see step 4).
- Stateful pieces as needed: a StatefulSet with `volumeClaimTemplates` for databases (see `apps/chesskernel/postgres.yaml`), a Deployment with `strategy: Recreate` and a single PVC for single-writer caches (see `apps/chesskernel/redis.yaml`).

Set resource `requests` and `limits` on every container. The node is 1 vCPU / 4 GB and CPU is the scarce resource; unbounded pods starve everything else. Copy the sizing in the existing apps as a baseline.

Images are pulled from GHCR as `ghcr.io/mateuseap/<name>-<component>:latest` with `imagePullPolicy: Always`. CI in the app's own repo builds and pushes `:latest` on merge; you roll out with `kubectl rollout restart` (see [Upgrading](#upgrading-components)).

## 2. The Application manifest in `argocd/`

Add `argocd/app-<name>.yaml`. Copy `argocd/app-chesskernel.yaml` and change the name, `path`, and destination namespace:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <name>
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2" # applications sync after the platform
spec:
  project: default
  source:
    repoURL: https://github.com/mateuseap/homelab
    targetRevision: main
    path: apps/<name>
  destination:
    server: https://kubernetes.default.svc
    namespace: <name>
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```

The `root` app-of-apps watches `argocd/`, so this file is all ArgoCD needs to start managing the app. Wave 2 keeps applications syncing after cert-manager, sealed-secrets, and monitoring are healthy.

If you want the namespace to carry a description and be protected from pruning like the others, add it to `platform/config/namespaces.yaml` with the `homelab.mateuseap.com/description` annotation and `argocd.argoproj.io/sync-options: Prune=false`. Otherwise `CreateNamespace=true` creates a bare namespace.

## 3. Sealed secret

Never commit plaintext secrets. Create a plaintext `Secret` in `/tmp`, seal it, commit the sealed output, and shred the plaintext.

```bash
cp docs/examples/chesskernel-secrets.example.yaml /tmp/secrets.yaml
# edit /tmp/secrets.yaml: set metadata.namespace to <name> and fill real values
kubeseal --controller-namespace kube-system --format yaml \
  < /tmp/secrets.yaml > apps/<name>/sealed-secrets.yaml
shred -u /tmp/secrets.yaml
```

The resulting `SealedSecret` is encrypted with the cluster's key and is safe in the public repo. Pods reference the decrypted `Secret` by name with `secretKeyRef`. See [ADR-003](../adr/003-sealed-secrets-for-public-repo.md) and the [security doc](../security/security.md) for the key backup and rotation model.

## 4. Ingress

Add an `Ingress` with `ingressClassName: traefik`, a `host:` rule under `*.lab.mateuseap.com`, and the cert-manager annotation:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  rules:
    - host: <name>.lab.mateuseap.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: client
                port: { number: 80 }
  tls:
    - hosts: [<name>.lab.mateuseap.com]
      secretName: <name>-tls
```

The wildcard record already resolves the host, so cert-manager issues its certificate over HTTP-01 on first request. If a service also needs a domain that does not yet resolve (as ChessKernel's lab host did before the wildcard existed), split it into a second Ingress so a pending certificate cannot drop TLS for the working host. See the [networking doc](../networking.md).

## 5. ServiceMonitor (metrics)

If the app exposes Prometheus metrics, add a `ServiceMonitor` so kube-prometheus-stack scrapes it. The pattern (from `apps/chesskernel/server.yaml`):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: <name>-server
  namespace: <name>
  labels:
    release: monitoring   # required: kube-prometheus-stack's selector matches this
spec:
  selector:
    matchLabels: { app: server }
  endpoints:
    - port: http          # a named port on the Service
      path: /metrics
      interval: 60s
  namespaceSelector:
    matchNames: [<name>]
```

Two things are load-bearing: the `release: monitoring` label (the operator only selects ServiceMonitors carrying it) and a **named** port on the Service (the endpoint references the port by name). `/metrics` is served on the cluster-internal Service port only; it is never added to the public ingress. LiveKit is a variant of the same pattern that scrapes its native metrics port (6789) by name.

Metrics become panels in the curated **Homelab Overview** dashboard (`platform/config/grafana-dashboard-homelab.yaml`), a ConfigMap labeled `grafana_dashboard: '1'` that Grafana's sidecar loads. To add panels, edit that dashboard JSON; do not enable the chart's default dashboards (they are noise on a single node).

## 6. Push

```bash
git checkout -b feat/<name>
git add apps/<name>/ argocd/app-<name>.yaml
git commit -m "feat: add <name>"
git push -u origin feat/<name>
```

Open a PR (see [CONTRIBUTING](../../CONTRIBUTING.md)). Once merged to `main`, ArgoCD syncs the new Application, cert-manager issues TLS, and the app comes up at `https://<name>.lab.mateuseap.com`. Watch it converge in the ArgoCD UI.

## Upgrading components

- **Application images** track `:latest`. CI pushes on merge; roll out with `kubectl -n <name> rollout restart deploy/server deploy/client`. Automating this with argocd-image-updater is a later milestone.
- **Helm-based platform components** (cert-manager, sealed-secrets, kube-prometheus-stack) are pinned by chart version in their `argocd/platform-*.yaml`. Upgrade by bumping `targetRevision`, reading the chart's changelog for CRD or values changes, and pushing. ArgoCD applies it. The monitoring app uses `ServerSideApply=true` because the Prometheus CRDs exceed the client-side apply size limit.
- **ArgoCD itself** is installed by `bootstrap/install.sh`, which tracks the `stable` channel (currently v3.4.5). Re-running the script upgrades it; the runtime trims (dex and notifications scaled to zero, `server.insecure=true`) are re-applied idempotently.
- **k3s** upgrades are node-level, done over SSH, outside GitOps.

Always change one component at a time and confirm the app returns green in ArgoCD and healthy in Grafana before moving on.
