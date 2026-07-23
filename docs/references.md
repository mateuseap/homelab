# References

Curated study links for the technologies this platform is built on, grouped by topic. Official documentation is preferred throughout. Use these to understand any component before changing it.

## Kubernetes

- [Kubernetes documentation](https://kubernetes.io/docs/home/)
- [Kubernetes concepts](https://kubernetes.io/docs/concepts/)
- [Workloads (Deployments, StatefulSets, CronJobs)](https://kubernetes.io/docs/concepts/workloads/)
- [Services, Load Balancing, and Networking](https://kubernetes.io/docs/concepts/services-networking/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [kubectl reference](https://kubernetes.io/docs/reference/kubectl/)

## k3s

- [k3s documentation](https://docs.k3s.io/)
- [k3s architecture](https://docs.k3s.io/architecture)
- [Networking (Traefik, ServiceLB, CoreDNS)](https://docs.k3s.io/networking/networking-services)
- [Storage and local-path-provisioner](https://docs.k3s.io/storage)

## GitOps and ArgoCD

- [OpenGitOps principles](https://opengitops.dev/)
- [Argo CD documentation](https://argo-cd.readthedocs.io/en/stable/)
- [App of apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sync phases and waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Sync options (Prune, ServerSideApply, CreateNamespace)](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)

## Helm

- [Helm documentation](https://helm.sh/docs/)
- [Charts guide](https://helm.sh/docs/topics/charts/)
- [Values files](https://helm.sh/docs/chart_template_guide/values_files/)

## cert-manager

- [cert-manager documentation](https://cert-manager.io/docs/)
- [ACME issuers](https://cert-manager.io/docs/configuration/acme/)
- [HTTP-01 challenge](https://cert-manager.io/docs/configuration/acme/http01/)
- [Securing Ingress resources](https://cert-manager.io/docs/usage/ingress/)

## Let's Encrypt and ACME

- [Let's Encrypt documentation](https://letsencrypt.org/docs/)
- [How it works (challenge types)](https://letsencrypt.org/how-it-works/)
- [Rate limits](https://letsencrypt.org/docs/rate-limits/)
- [ACME protocol (RFC 8555)](https://datatracker.ietf.org/doc/html/rfc8555)

## Sealed Secrets

- [sealed-secrets (Bitnami Labs)](https://github.com/bitnami-labs/sealed-secrets)
- [README: usage and kubeseal](https://github.com/bitnami-labs/sealed-secrets#usage)
- [Secret rotation and key management](https://github.com/bitnami-labs/sealed-secrets#secret-rotation)

## Traefik

- [Traefik Proxy documentation](https://doc.traefik.io/traefik/)
- [Kubernetes Ingress provider](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)
- [Routers and TLS](https://doc.traefik.io/traefik/routing/routers/)

## Prometheus

- [Prometheus documentation](https://prometheus.io/docs/introduction/overview/)
- [Querying basics (PromQL)](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Prometheus Operator (ServiceMonitor)](https://prometheus-operator.dev/docs/developer/getting-started/)
- [node_exporter](https://github.com/prometheus/node_exporter)

## Grafana and PromQL

- [Grafana documentation](https://grafana.com/docs/grafana/latest/)
- [Panels and visualizations](https://grafana.com/docs/grafana/latest/panels-visualizations/)
- [Provision dashboards](https://grafana.com/docs/grafana/latest/administration/provisioning/#dashboards)
- [PromQL query examples](https://prometheus.io/docs/prometheus/latest/querying/examples/)

## kube-prometheus-stack

- [kube-prometheus-stack chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Default values](https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml)
- [kube-prometheus project](https://github.com/prometheus-operator/kube-prometheus)

## Cloudflare R2 and the S3 API

- [Cloudflare R2 documentation](https://developers.cloudflare.com/r2/)
- [S3 API compatibility](https://developers.cloudflare.com/r2/api/s3/api/)
- [Using aws-cli with R2](https://developers.cloudflare.com/r2/examples/aws/aws-cli/)
- [R2 API tokens](https://developers.cloudflare.com/r2/api/tokens/)

## Docker

- [Docker documentation](https://docs.docker.com/)
- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
- [Multi-stage builds](https://docs.docker.com/build/building/multi-stage/)

## GitHub Container Registry (GHCR)

- [Working with the Container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Publishing Docker images with Actions](https://docs.github.com/en/actions/how-tos/use-cases-and-examples/publishing-packages/publishing-docker-images)
