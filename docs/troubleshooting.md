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

## Longhorn Helm Sync Attempts a Downgrade

Symptom: `longhorn-helm` is healthy at runtime but `OutOfSync`, and its ArgoCD
operation fails after repeated attempts to run `longhorn-pre-upgrade`. The live
Longhorn workloads may remain healthy on a newer chart revision.

Before retrying the sync, compare the desired chart revision with the revisions
in the Application history:

```bash
kubectl -n argocd get application longhorn-helm \
  -o jsonpath='{.spec.source.targetRevision}{"\n"}{range .status.history[*]}{.deployedAt}{"\t"}{.revision}{"\n"}{end}'
```

An exact pin can become a downgrade request when it reaches the cluster after a
wildcard revision has already allowed a newer chart to deploy. On 2026-08-16,
Longhorn `1.12.1` had been running since 2026-08-14, but the later-reconciled Git
state pinned `1.12.0`. ArgoCD then attempted `1.12.0`; the pre-upgrade Job
reached its backoff limit after five retries. The Job's exact error output was
no longer retained, so the history proves the downgrade trigger but not the
hook's internal rejection reason.

Recover in Git:

1. Move `spec.source.targetRevision` forward to the deliberately selected
   revision. Do not force the live release back to the stale pin.
2. Set `preUpgradeChecker.jobEnabled: false` in the Longhorn Helm values.
   Longhorn's chart explicitly directs ArgoCD and other GitOps installations to
   disable this hook.
3. Preserve `prune: false` on both the parent and nested Longhorn Applications.
4. Commit and push the convergent desired state, then let ArgoCD retry it.

If the live release already matches the corrected revision, ArgoCD may become
`Synced` and `Healthy` without starting a new operation. Its historical
`operationState` can then remain `Failed`, which keeps Radar's
`gitops_operation_failed` issue active. Verify that the desired revision, live
chart version, and rendered resources agree before clearing that history. Then
run one no-prune sync of the convergent revision:

```bash
argocd app sync longhorn-helm \
  --app-namespace argocd \
  --revision <matching-revision>
```

If an ArgoCD API session is unavailable, the Kubernetes-side equivalent is a
one-time operation request. Keep `prune: false`, use the already-verified
revision, and do not use this to force a downgrade:

```bash
kubectl -n argocd patch application longhorn-helm --type=merge \
  -p '{"operation":{"sync":{"revision":"<matching-revision>","prune":false,"syncOptions":["CreateNamespace=true","ServerSideApply=true","SkipDryRunOnMissingResource=true"]}}}'
```

ArgoCD removes the requested operation after processing it. Confirm the new
`operationState.phase` is `Succeeded` and Radar no longer reports the failed
operation.

The chart instruction is recorded in the
[Longhorn `1.12.0` values](https://github.com/longhorn/longhorn/blob/v1.12.0/chart/values.yaml).

## Radar Shows No CPU or Memory Samples While Netdata Is Healthy

Symptom: Radar's Capacity view renders scheduling capacity, but actual usage is
unavailable and MCP `top_resources` reports `metricsAvailable: false`. Netdata
can still show healthy CPU, memory, disk, and Kubernetes cgroup telemetry.

These are separate data paths. Radar's cluster scheduling ledger uses node
allocatable capacity and pod requests, so it works without a metrics backend.
Actual CPU and memory samples require the Kubernetes Metrics API, while Radar's
PromQL views require a configured Prometheus-compatible endpoint. Netdata
collecting the same class of telemetry does not automatically connect it to
Radar. Treat unavailable usage as unknown, not zero; Radar documents this
separation in its [Capacity guide](https://radarhq.io/docs/features/capacity).

This repository currently sets `rbac.metrics: false` for Radar. The
2026-08-16 runtime check also found no `metrics.k8s.io` APIService and no
connected Prometheus service. Installing metrics-server alone would therefore
remain insufficient because Radar's ServiceAccount would still receive `403`
responses.

Enabling live CPU and memory widgets is a separate reviewed change that must do
both of the following:

1. Install and validate metrics-server so `metrics.k8s.io` is available.
2. Set Radar `rbac.metrics: true` so its ServiceAccount can read that API.

Configure Radar's Prometheus integration separately when PromQL or historical
metrics are wanted. Validate the Metrics API before diagnosing Radar itself:

```bash
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes
```

## Radar Reports Longhorn PDBs Blocking Evictions

Symptom: Radar reports one warning for each Longhorn instance-manager
PodDisruptionBudget because it selects one healthy pod and permits zero
voluntary disruptions.

This is expected storage protection, not an active workload failure. Longhorn
uses strict instance-manager PDBs to prevent a drain from evicting the last
healthy process serving attached volumes. Do not apply Radar's generic advice
to relax these PDBs during normal operation.

For planned node maintenance, verify volume and replica health and follow
Longhorn's controlled drain procedure. A blocked drain is a maintenance gate
to investigate, not evidence that the PDB should be weakened. See Longhorn's
[maintenance guidance](https://longhorn.io/docs/1.12.0/maintenance/maintenance/)
and [PDB behavior with cluster autoscaling](https://longhorn.io/docs/1.12.0/high-availability/k8s-cluster-autoscaler/).

## Phoenix Experiments Time Out While Manual Playground Runs Succeed

Symptom: Phoenix server-side experiments produce terminal `timeout after 3
retries` rows or no output for some examples, while the same provider and proxy
complete manual Playground requests. Proxy logs may show successful status 200
responses with short latency even when Phoenix later records a timeout.

Do not infer an authentication or network refusal from the missing experiment
output alone. Phoenix 20.4.0 applies a 120-second wall-clock deadline around the
complete streamed response. Its timeout path retries the task but does not
persist the partial span or token counts. The deployed Anthropic OAuth proxy's
`request completed` log is also header-time, not stream-completion time.

First, identify the Phoenix timeout cadence:

```bash
kubectl -n phoenix logs deploy/phoenix-helm --since=24h \
  | rg 'TaskWorkItem .* timed out|circuit breaker'
```

Approximately 120-second waves support the caller-deadline path. Immediate
401, 403, or 429 responses, failed token refreshes, account cooldown, upstream
5xx responses, or a failing tailnet health check instead support transport,
authentication, or provider hypotheses and must be investigated separately.

For completed comparison runs, inspect both wall-clock latency and completion
tokens. Do not treat a timed-out run with no persisted span as zero duration or
zero generated tokens. A manual span longer than 120 seconds can complete
successfully because the Playground request is not under the server-side
experiment deadline.

Mitigation remains a reviewed choice: verify a client-side experiment path,
shorten the requested deliverable and measure it, or adopt a supported
configurable timeout if Phoenix exposes one. Do not set a low `max_tokens`
value merely to fit the deadline; it can truncate the final sections rather
than make the response concise.

The full evidence, rejected hypotheses, and open corrective actions are in the
[2026-08-27 incident report](incidents/2026-08-27-phoenix-experiment-timeouts.md).

## Radar Repeats Argo Application “Spec Changed”

Symptom: Radar records an ArgoCD Application generation change every few
minutes and classifies it as an unspecified spec or configuration change, even
when no Git commit or field-level spec change occurred.

Check whether the installed Application CRD exposes a status subresource:

```bash
kubectl get crd applications.argoproj.io \
  -o jsonpath='{range .spec.versions[*]}{.name}{"\t"}{.subresources}{"\n"}{end}'
```

On 2026-08-16, every live Application showed this cadence and the storage
version of the CRD had `subresources: {}`. Without a `/status` subresource,
normal controller status writes update the main custom resource and can advance
`metadata.generation`. Radar sees the generation change but has no field-level
record, so its generic label is not proof that `.spec` changed. Kubernetes
documents the generation and status-subresource behavior in its
[CRD reference](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/).

Treat this explanation as high-confidence unless an audit log or consecutive
raw-object diff proves the changing field. Before responding to a Radar record,
inspect the ArgoCD desired-versus-live diff and the Application's actual `spec`.
A generation-only record should not trigger a sync or rollback.

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
      jqPathExpressions:
        - .spec.data[].remoteRef.conversionStrategy
        - .spec.data[].remoteRef.decodingStrategy
        - .spec.data[].remoteRef.metadataPolicy
```

The wildcard covers every `spec.data` entry, including keys added later. Do not
use index-specific JSON pointers: they silently stop covering entries beyond
the enumerated indexes. Also set `RespectIgnoreDifferences=true` on the
Application.

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
