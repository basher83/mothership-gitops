# GitOps Troubleshooting

This guide covers application and platform reconciliation issues owned by
mothership-gitops. Omni, the Proxmox provider, machine classes, cluster
templates, SideroLink, split-horizon DNS, and Talos node substrate issues live
in `../Omni-Scale`.

## ArgoCD Redis HA Replica Pending

Symptom: `argocd-redis-ha-server-2` remains Pending and the HAProxy replica may
also remain Pending.

The common event looks like this:

```text
0/5 nodes are available:
3 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: },
2 node(s) didn't match pod anti-affinity rules
```

Redis HA uses three replicas with pod anti-affinity. If the cluster has three
tainted control-plane nodes and only two workers, only two schedulable nodes
exist. The application symptom belongs here, but the fix crosses into
Omni-Scale because worker capacity is substrate.

The preferred fix is to add a third worker in `../Omni-Scale` by applying the
appropriate MachineClass and syncing `clusters/talos-prod-01.yaml`. Then let
ArgoCD reconcile the HA app again. Alternatives are to reduce Redis HA replicas
or add tolerations, but both weaken the original HA intent.

## Application Stuck Progressing

Symptom: an ArgoCD Application stays in `Progressing`.

Common causes are an Ingress resource without an active controller/address, or
a Deployment waiting on pods that cannot schedule because of resource requests,
node selectors, taints, or anti-affinity.

If a chart creates an Ingress that this repo does not use, disable the chart's
built-in ingress and use a local Tailscale Ingress manifest instead:

```yaml
helm:
  valuesObject:
    ingress:
      enabled: false
```

If pods cannot schedule because the cluster lacks schedulable workers, fix the
machine classes or cluster template in `../Omni-Scale`.

## ExternalSecret Causes Parent App OutOfSync

Symptom: the parent Application shows `OutOfSync` while child Helm apps are
Synced. The `ExternalSecret` resource appears drifted.

External Secrets Operator adds default fields that are not normally committed
to git:

- `conversionStrategy: Default`
- `decodingStrategy: None`
- `metadataPolicy: None`

Add `ignoreDifferences` to the parent Application:

```yaml
spec:
  ignoreDifferences:
    - group: external-secrets.io
      kind: ExternalSecret
      jsonPointers:
        - /spec/data/0/remoteRef/conversionStrategy
        - /spec/data/0/remoteRef/decodingStrategy
        - /spec/data/0/remoteRef/metadataPolicy
        - /spec/data/1/remoteRef/conversionStrategy
        - /spec/data/1/remoteRef/decodingStrategy
        - /spec/data/1/remoteRef/metadataPolicy
```

Also set `RespectIgnoreDifferences=true` on the Application when needed.

## Helm App Drifts From ESO-Managed Secret

Symptom: a Helm Application repeatedly flips between `OutOfSync` and `Synced`
because a Secret created by an `ExternalSecret` changes.

When a chart references an `existingSecret` created by ESO, ESO refreshes the
Secret and ArgoCD may detect drift. Add an ignore rule for that Secret:

```yaml
spec:
  ignoreDifferences:
    - group: ""
      kind: Secret
      name: <secret-name>
      jsonPointers:
        - /data
        - /metadata/annotations
        - /metadata/labels
  syncPolicy:
    syncOptions:
      - RespectIgnoreDifferences=true
```

## Tailscale Proxy Pods Hit PodSecurity

Symptom: Tailscale proxy pods fail to create with a PodSecurity violation.

```text
pods "ts-xxx-0" is forbidden: violates PodSecurity "baseline:latest": privileged
```

Tailscale proxy pods need privileged networking. Label the namespace to allow
privileged pods. This repo carries that pattern in
`apps/tailscale-operator/namespace.yaml`.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tailscale-operator
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
```

## Helm Chart Does Not Propagate Service Annotations

Symptom: Tailscale exposure annotations in Helm values do not appear on the
deployed Service.

Some Helm charts do not template service annotations or use a non-standard
value path. Prefer a local Tailscale Ingress manifest where possible. If service
annotations are required, add an ArgoCD ignore rule to preserve operator-managed
or manually applied annotations:

```yaml
spec:
  ignoreDifferences:
    - group: ""
      kind: Service
      name: <service-name>
      jsonPointers:
        - /metadata/annotations/tailscale.com~1expose
        - /metadata/annotations/tailscale.com~1hostname
        - /metadata/finalizers
```

The `~1` sequence is JSON Pointer encoding for `/` in annotation keys.

## Tailscale Service Exposure Uses Backend Port

Symptom: a Service exposed via `tailscale.com/expose` requires a port in the URL,
such as `http://myapp.tailnet.ts.net:8080`.

Service annotation exposure forwards the backend port. It does not remap to
HTTPS on 443. For browser UIs, use Tailscale Ingress instead:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: myapp
spec:
  ingressClassName: tailscale
  defaultBackend:
    service:
      name: myapp-service
      port:
        number: 8080
  tls:
    - hosts:
        - myapp
```

Tailscale Ingress serves on port 443 with automatic TLS and avoids port suffixes
in browser URLs. First access can be slow while the certificate is provisioned.

## Deployment Strategy Change Stuck (ServerSideApply)

Symptom: changing a Deployment's `strategy.type` between `RollingUpdate` and
`Recreate` leaves the Application stuck; ArgoCD retries and gives up, and the
deployment keeps the old strategy.

ServerSideApply patches the `type` field but does not remove the stale
`rollingUpdate` sub-fields, and Kubernetes rejects the apply because
`rollingUpdate` is forbidden when type is `Recreate`.

Fix with a JSON patch to remove the stale fields:

```bash
kubectl patch deployment <name> -n <ns> --type='json' \
  -p='[{"op":"remove","path":"/spec/strategy/rollingUpdate"},{"op":"replace","path":"/spec/strategy/type","value":"Recreate"}]'
```

Alternatively, force a full resource replacement:

```bash
argocd app sync <app> --replace
```

Prevention: when a chart needs `Recreate`, also set `rollingUpdate: null` in
values so SSA clears the sub-fields (see `apps/phoenix/application.yaml`).

## Helm Chart Value Gotchas

Symptom: a Helm value appears correct but has no effect on the deployed
resources.

Some charts use non-obvious value keys. Always verify against the chart's
actual `values.yaml`. Known cases in this repo:

**Homarr** (`homarr-labs/homarr`) — persistence key is `homarrDatabase`,
not `database`:

```yaml
persistence:
  homarrDatabase:        # NOT persistence.database
    enabled: true
    storageClassName: longhorn
```

**ArgoCD Redis HA** (`argo/argo-cd` with `redis-ha.enabled`) — persistence
key is `persistentVolume`, not `persistence`:

```yaml
redis-ha:
  enabled: true
  persistentVolume:      # NOT redis-ha.persistence
    enabled: true
    storageClass: longhorn
```
