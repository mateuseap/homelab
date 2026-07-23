# ADR-001: k3s over Full or Managed Kubernetes

**Status:** Accepted  
**Date:** 2026-07-23

## Context

The platform runs on a single VPS with 1 vCPU and 4 GB of RAM (179.197.71.43). Kubernetes is an explicit goal of the project: it is a learning and portfolio exercise, not only a deployment mechanism. The question is which Kubernetes distribution fits a node that small.

Three options were considered:

- **Full upstream Kubernetes (kubeadm).** Separate etcd, kube-apiserver, controller-manager, scheduler, and a CNI to install and maintain. The control plane alone wants more than 2 GB and multiple cores before any workload runs.
- **Managed Kubernetes (EKS/GKE/AKS or a managed control plane).** Removes the control-plane burden but adds a monthly bill, moves the cluster off a machine I fully own, and hides the internals I want to learn.
- **k3s.** A CNCF-graduated, fully conformant Kubernetes distribution packaged as a single binary. It replaces etcd with SQLite by default, runs the control plane and kubelet in one process, and bundles Traefik, CoreDNS, local-path storage, and a service load balancer.

## Decision

Use **k3s**, single node, with its bundled components.

- The control plane fits in roughly 600 MB, leaving headroom for ArgoCD, monitoring, and both applications on 4 GB.
- The API is the same Kubernetes API, so every manifest, ADR, and skill transfers to a full cluster later.
- Bundled Traefik, CoreDNS, and local-path storage remove three install steps and three things to maintain.
- Because the datastore is SQLite rather than etcd, the monitoring stack disables the `kubeEtcd` scrape target (see `platform/monitoring/values.yaml`).

## Consequences

- Single node means no high availability. This is accepted; HA on one VPS is impossible by definition (see ADR-006 for how data survives node loss).
- The node IP equals the public IP on a single-NIC VPS, so kubelet (10250) and the API (6443) are reachable from the internet. They are authenticated, but a provider-level firewall is the recommended defense in depth (see the security doc).
- Control-plane components run inside the single k3s process and do not expose separate scrape endpoints, so `kubeControllerManager`, `kubeScheduler`, and `kubeProxy` monitoring targets are turned off to avoid noise.
- Storage is node-local (local-path). A rebuilt node starts empty and is repopulated from git plus the nightly backup, not from a replicated volume.
