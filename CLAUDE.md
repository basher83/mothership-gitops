# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Run `/omni-scale:omni-prime` at session start for operational context (MCP tools, validation patterns).**

## Repository Overview

GitOps manifests for `talos-prod-01` Kubernetes cluster using ArgoCD App of Apps pattern with sync waves.

## Deployment Standards

### Web UI Exposure (HARD REQUIREMENT)

Any application with a web UI MUST include a Tailscale Ingress for external
access.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <app>-tailscale
  namespace: <app-namespace>
spec:
  ingressClassName: tailscale
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <frontend-service>
                port:
                  number: 80
```

**IMPORTANT**: Do NOT deploy web UIs as cluster-internal only. If it has a UI, it gets exposed.

## Architecture

Single bootstrap command deploys the entire platform through ordered sync waves:

```text
Wave 1:  ArgoCD (non-HA bootstrap)
Wave 2:  Root App of Apps, External Secrets Operator, ClusterSecretStores
Wave 4:  Tailscale Operator (network ingress)
Wave 5:  Longhorn (distributed storage)
Wave 6:  Netdata (monitoring)
Wave 7:  Homarr (dashboard)
Wave 99: ArgoCD HA upgrade (manual sync required)
```

All applications use automated sync with prune and self-heal except ArgoCD HA which requires manual trigger after Longhorn is healthy.

## Key Patterns

### Adding a New Application

1. Create directory under `apps/<app-name>/`
2. Add `application.yaml` with Helm chart source and values
3. If app needs secrets: add `externalsecret.yaml` referencing the appropriate ClusterSecretStore
4. Add Application manifest to `apps/root.yaml` with appropriate sync-wave annotation
5. If using ExternalSecrets, add `ignoreDifferences` for ESO default fields to prevent reconciliation loops

### ExternalSecrets Integration

Secrets flow from Infisical through External Secrets Operator. Each secrets path has its own ClusterSecretStore:

- `infisical-tailscale` → `/tailscale-operator`
- `infisical-netdata` → `/netdata`
- `infisical-homarr` → `/homarr`

To add secrets for a new app:

1. Add secrets to Infisical under `/app-name` path in `mothership-s0-ew` project (prod environment)
2. Add a ClusterSecretStore to `apps/external-secrets/clustersecretstore.yaml`
3. Create ExternalSecret in the app's directory with `sync-wave: "0"` (deploys before the app within its wave)

### ArgoCD ignoreDifferences

When an Application uses ExternalSecrets, add this to prevent sync loops from ESO default values:

```yaml
ignoreDifferences:
  - group: external-secrets.io
    kind: ExternalSecret
    jsonPointers:
      - /spec/data/0/remoteRef/conversionStrategy
      - /spec/data/0/remoteRef/decodingStrategy
      - /spec/data/0/remoteRef/metadataPolicy
```

Add entries for each data item index (0, 1, 2...).

### Ingress via Tailscale

Apps exposed externally use Tailscale Ingress class with automatic TLS. See `apps/homarr/ingress.yaml` for pattern.

### Egress to Tailnet Hosts

For pods that need to reach Tailscale-connected hosts (e.g., Homarr → Proxmox APIs), use the egress + DNS pattern:

1. **Egress Service** — Creates a Tailscale proxy for the target host:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: proxmox-foxtrot
     namespace: homarr
     annotations:
       tailscale.com/tailnet-fqdn: foxtrot.tailfb3ea.ts.net
   spec:
     type: ExternalName
     externalName: placeholder
   ```

2. **DNSConfig** — Deploys Tailscale nameserver for MagicDNS resolution:
   ```yaml
   apiVersion: tailscale.com/v1alpha1
   kind: DNSConfig
   metadata:
     name: ts-dns
     namespace: tailscale-operator
   spec:
     nameserver:
       image:
         repo: tailscale/k8s-nameserver
         tag: unstable
   ```

3. **CoreDNS** — Forward `*.ts.net` queries to the nameserver (IP from `kubectl get svc nameserver -n tailscale-operator`):
   ```
   ts.net:53 {
       forward . <nameserver-clusterip>
       cache 30
   }
   ```

With this setup, pods connect using the actual tailnet FQDN (`https://foxtrot.tailfb3ea.ts.net`), preserving SNI for valid TLS with Tailscale Serve.

**Note:** CoreDNS patch on Talos is volatile — may need reapplication after upgrades.

### Storage

Longhorn provides the default StorageClass. PVCs use `ReadWriteOnce` access mode.

### Helm Chart Value Gotchas

Some Helm charts use non-obvious value keys. Always verify against the chart's `values.yaml`:

**Homarr** (`homarr-labs/homarr`):
```yaml
persistence:
  homarrDatabase:        # NOT persistence.database
    enabled: true
    storageClassName: longhorn
```

**ArgoCD Redis HA** (`argo/argo-cd` with `redis-ha.enabled`):
```yaml
redis-ha:
  enabled: true
  persistentVolume:      # NOT redis-ha.persistence
    enabled: true
    storageClass: longhorn
```

## Bootstrap

Requires `kubectl` configured via Omni proxy and Infisical Machine Identity credentials.

```bash
# Create manual secret (only secret not managed by GitOps)
kubectl create namespace external-secrets
kubectl create secret generic universal-auth-credentials \
  --from-literal=clientId=<INFISICAL_CLIENT_ID> \
  --from-literal=clientSecret=<INFISICAL_CLIENT_SECRET> \
  -n external-secrets

# Deploy everything
kubectl apply -f bootstrap/bootstrap.yaml

# Monitor
watch kubectl get applications -n argocd

# After Longhorn healthy, trigger HA upgrade
argocd app sync argocd-ha
```

## Related Infrastructure

- [Omni-Scale](https://github.com/basher83/Omni-Scale) - Talos cluster provisioning via Omni
- Infisical project `mothership-s0-ew` - Secrets management
