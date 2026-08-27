# mothership-gitops

GitOps manifests for `talos-prod-01` Kubernetes cluster.

## Repo Boundary

This repo answers: what runs on the cluster after the Omni-managed Talos
substrate exists?

mothership-gitops owns ArgoCD App of Apps reconciliation, sync waves, Longhorn
Helm values, backup schedules, StorageClasses, ESO/Infisical wiring, Tailscale
Operator manifests, ingress exposure, monitoring, dashboards, and workload
applications.

It does not own the Omni substrate. Sidero Omni self-hosting, the Proxmox
infrastructure provider, cluster templates, machine classes, Talos node
requirements, SideroLink/DNS/Tailscale access constraints, and provider
troubleshooting live in `../Omni-Scale`. This repo may reference substrate
constraints when they affect platform bootstrap, such as the required Cilium
MTU override, but Omni-Scale is the source of truth for why those constraints
exist.

## Architecture

App of Apps pattern with sync waves. Bootstrap installs prerequisites first,
then ArgoCD reconciles:

1. ArgoCD (non-HA via Helm)
2. External Secrets Operator + Infisical ClusterSecretStores
3. Tailscale Operator + Ingress for ArgoCD
4. Longhorn (distributed storage) + Ingress
5. Netdata (monitoring)
6. Radar (Kubernetes UI and MCP server)
7. Homarr (homelab dashboard)
8. Anthropic OAuth Proxy (tailnet-microservices Kustomize)
9. Phoenix (LLM observability eval backend)
10. ArgoCD HA upgrade (manual trigger)

All web UIs exposed via Tailscale Ingress (no public exposure).

## Bootstrap

The bootstrap requires pre-installing CNI, ESO, and Longhorn via Helm before
ArgoCD can manage them. This breaks a chicken-and-egg: ArgoCD needs CNI to
schedule, ESO needs CRDs before ClusterSecretStores, Longhorn hooks need the
ServiceAccount the chart creates.

### Prerequisites

- `kubectl` configured via Omni proxy
- `helm` CLI
- Infisical Universal Auth credentials (Machine Identity)

### Deploy

```bash
# 1. Create bootstrap secret for ESO
kubectl create namespace external-secrets
kubectl create secret generic universal-auth-credentials \
  --from-literal=clientId=<INFISICAL_CLIENT_ID> \
  --from-literal=clientSecret=<INFISICAL_CLIENT_SECRET> \
  -n external-secrets

# 2. Install Cilium CNI (required before ArgoCD can schedule)
#
# MTU=1450 is MANDATORY. Omni's siderolink WireGuard tunnel runs at MTU 1280,
# which Cilium will auto-detect and apply to every pod veth cluster-wide,
# strangling all traffic through Tailscale Ingress (~22 KB/s vs ~99 Mbps).
# Never omit --set MTU=1450. See Omni-Scale/docs/guides/CILIUM.md.
CP_IP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
kubectl label namespace kube-system pod-security.kubernetes.io/enforce=privileged
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium -n kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set MTU=1450 \
  --set k8sServiceHost=$CP_IP \
  --set k8sServicePort=6443 \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set securityContext.privileged=true

# Wait for nodes Ready
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# 3. Install ESO (CRDs before app-of-apps syncs ClusterSecretStores)
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --set installCRDs=true

# 4. Create privileged namespaces and install Longhorn
kubectl create namespace longhorn-system
kubectl create namespace netdata
kubectl label namespace longhorn-system pod-security.kubernetes.io/enforce=privileged
kubectl label namespace netdata pod-security.kubernetes.io/enforce=privileged
helm repo add longhorn https://charts.longhorn.io
helm install longhorn longhorn/longhorn -n longhorn-system --no-hooks

# 5. Install ArgoCD via Helm
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace \
  --set configs.params."server\.insecure"=true \
  --set global.networkPolicy.create=false

# 6. Bootstrap app-of-apps
kubectl apply -f https://raw.githubusercontent.com/basher83/mothership-gitops/main/bootstrap/bootstrap.yaml

# 7. Monitor sync progress
watch kubectl get applications -n argocd

# 8. After all apps healthy, trigger HA upgrade
kubectl patch application argocd-ha -n argocd --type merge \
  -p '{"operation":{"sync":{}}}'
kubectl patch application argocd-ha-helm -n argocd --type merge \
  -p '{"operation":{"sync":{}}}'
```

## Recovery

Full cluster rebuild from Git:

1. Rebuild cluster via Omni (use Omni-Scale `/omni-scale:disaster-recovery`)
2. Follow Deploy steps above
3. Wait for all apps synced

Workload data in Longhorn is lost unless backed up to S3.

## Structure

```text
bootstrap/
  bootstrap.yaml        # Entry point (ArgoCD + root app)
apps/
  root.yaml             # App of Apps orchestrator
  argocd/               # HA upgrade (wave 99, manual)
  argocd-ingress/       # Tailscale Ingress for ArgoCD (wave 4)
  external-secrets/     # ESO + ClusterSecretStores (root wave 2, child waves 1-2)
  tailscale-operator/   # Tailscale Operator (wave 4)
  longhorn/             # Storage + Ingress (wave 5)
  netdata/              # Monitoring + Ingress (wave 6)
  radar/                # Kubernetes UI + MCP + Ingress (wave 6)
  homarr/               # Dashboard + Ingress (wave 7)
  anthropic-oauth-proxy.yaml  # External-source app (wave 8)
  phoenix/              # LLM observability + Ingress (wave 9)
docs/
  adrs/                 # Architecture decisions and supersession history
  incidents/            # Historical incident reports and follow-up status
```

## Related

- [Omni-Scale](https://github.com/basher83/Omni-Scale) - Infrastructure provisioning
- [Architecture](docs/architecture.md) - Sync waves, sync policy exceptions
- [Architecture Decisions](docs/adrs/README.md) - Accepted and superseded ADRs
- [Incident Reports](docs/incidents/README.md) - Evidence-bounded incident
  timelines, causes, and follow-up status
- [Adding Applications](docs/adding-applications.md) - New app checklist,
  ExternalSecrets wiring, UI exposure requirement
- [Tailscale Networking](docs/tailscale-networking.md) - Ingress and
  egress-to-tailnet patterns
- [Radar Deployment Specification](specs/radar-in-cluster.md) - Access,
  persistence, MCP, and validation contract
- [Backup Storage](docs/backup-storage.md) - Longhorn backup tiers, MinIO S3
- [Troubleshooting](docs/troubleshooting.md) - ArgoCD, ESO, Tailscale
  Ingress, SSA, and Helm chart gotchas
- [Infisical](https://app.infisical.com) - Secrets management (project: `mothership-s0-ew`)
