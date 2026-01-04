# mothership-gitops

GitOps manifests for `talos-prod-01` Kubernetes cluster.

## Architecture

App of Apps pattern with sync waves. Single bootstrap command deploys:

1. ArgoCD (non-HA)
2. External Secrets Operator + Infisical ClusterSecretStore
3. Tailscale Operator
4. Longhorn (distributed storage)
5. Netdata (monitoring)
6. ArgoCD HA upgrade (manual trigger)

## Bootstrap

### Prerequisites

- `kubectl` configured via Omni proxy
- Infisical Universal Auth credentials (Machine Identity)

### Deploy

```bash
# Step 1: Create the one manual secret
kubectl create namespace external-secrets
kubectl create secret generic universal-auth-credentials \
  --from-literal=clientId=<INFISICAL_CLIENT_ID> \
  --from-literal=clientSecret=<INFISICAL_CLIENT_SECRET> \
  -n external-secrets

# Step 2: Bootstrap
kubectl apply -f bootstrap/bootstrap.yaml

# Step 3: Monitor
watch kubectl get applications -n argocd

# Step 4: After Longhorn healthy, trigger HA upgrade
argocd app sync argocd-ha
```

## Recovery

Full cluster rebuild from Git:

1. Rebuild cluster via Omni (`specs/omni.yaml` in Omni-Scale repo)
2. Run bootstrap Step 1 (manual secret)
3. Run bootstrap Step 2 (`kubectl apply`)
4. Wait for sync

Workload data in Longhorn is lost unless backed up externally.

## Structure

```text
bootstrap/
  bootstrap.yaml      # Entry point
apps/
  root.yaml           # App of Apps
  argocd/             # HA upgrade (wave 99)
  external-secrets/   # ESO + ClusterSecretStore (wave 2-3)
  tailscale-operator/ # Tailscale (wave 4)
  longhorn/           # Storage (wave 5)
  netdata/            # Monitoring (wave 6)
```

## Related

- [Omni-Scale](https://github.com/basher83/Omni-Scale) - Infrastructure provisioning
- [Infisical](https://app.infisical.com) - Secrets management (project: `mothership-s0-ew`)
