# mothership-gitops

GitOps manifests for `talos-prod-01` Kubernetes cluster.

## Architecture

App of Apps pattern with sync waves. Single bootstrap command deploys:

1. ArgoCD (non-HA via Helm)
2. External Secrets Operator + Infisical ClusterSecretStores
3. Tailscale Operator + Ingress for ArgoCD
4. Longhorn (distributed storage) + Ingress
5. Netdata (monitoring)
6. Homarr (homelab dashboard)
7. ArgoCD HA upgrade (manual trigger)

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
CP_IP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
kubectl label namespace kube-system pod-security.kubernetes.io/enforce=privileged
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium -n kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
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
  external-secrets/     # ESO + ClusterSecretStores (wave 2-3)
  tailscale-operator/   # Tailscale Operator (wave 4)
  longhorn/             # Storage + Ingress (wave 5)
  netdata/              # Monitoring + Ingress (wave 6)
  homarr/               # Dashboard + Ingress (wave 7)
```

## Related

- [Omni-Scale](https://github.com/basher83/Omni-Scale) - Infrastructure provisioning
- [Infisical](https://app.infisical.com) - Secrets management (project: `mothership-s0-ew`)
