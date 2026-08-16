# Spec: Radar In-Cluster Deployment

| Field | Value |
|---|---|
| Status | Implemented and runtime-validated, including ArgoCD deep diff and cross-restart SQLite retention |
| Created | 2026-08-16 |
| Scope | Single-cluster, single-operator Radar OSS deployment on `talos-prod-01` |

## Purpose

Deploy Radar directly into the homelab as an always-on Kubernetes UI and MCP
server. The deployment complements the existing `kubectl` and Kubernetes MCP
paths with Radar's token-optimized issues, topology, events, logs, timeline,
resource relationships, and canonical ArgoCD desired-versus-live diffs. It is
not a pre-production pilot: the homelab is the proving ground.

This document records the selected design, declarative manifests, and dated
runtime evidence. It does not make personal MCP client configuration part of
the repository or authorize future capability expansion.

## Operator Decisions

- Radar is for one operator, not a multi-user team.
- Deploy in-cluster immediately rather than running a separate local trial.
- Tailscale is the user-access boundary; do not add Radar OIDC or proxy auth.
- Enable MCP. The operator accepts responsibility for connecting clients and
  invoking tools; an agent confirmation prompt is not a security boundary.
- Connect Radar to the in-cluster ArgoCD API with a dedicated, get-only local
  account. Deliver its token through Infisical and External Secrets Operator;
  do not save an admin or personal token through the Radar UI.
- Use Radar's chart-managed, read-only ServiceAccount permissions. Do not grant
  Secrets, Helm writes, pod exec, port-forward, self-upgrade, or node-operation
  permissions.
- Keep pod-log reads enabled.
- Persist the timeline with SQLite on Longhorn so pod restarts do not erase
  event history.
- Pin the chart exactly and require manual review for every Radar update.
- Deploy with the repository's default automated sync, prune, and self-heal
  policy.

## Goals

1. Serve the Radar UI only through a Tailscale Ingress.
2. Serve the Radar MCP endpoint through the same trusted tailnet path.
3. Provide cluster-wide read-only topology, issue, event, resource, ArgoCD CRD,
   and pod-log visibility.
4. Provide canonical Git-rendered desired-versus-live diffs through a
   dedicated ArgoCD API account without granting sync or mutation authority.
5. Persist timeline history across normal pod restarts, targeting seven days
   subject to the configured storage cap.
6. Prevent ordinary cluster workloads from bypassing Tailscale through the
   Radar ClusterIP.
7. Keep the deployment declarative and recoverable through ArgoCD.

## Non-Goals

- Multi-user authentication, per-user impersonation, or new human Kubernetes
  RBAC mappings.
- Radar Cloud or any outbound cluster-data tunnel.
- Secret browsing, Helm mutation, workload mutation, pod exec, port-forward,
  node operations, or self-upgrade through Radar.
- Installing metrics-server, Prometheus, VictoriaMetrics, OpenCost, Hubble
  Relay, or another telemetry dependency as part of this change.
- Granting the ArgoCD account permission to sync, update, delete, invoke
  actions, override, or otherwise mutate Applications. The token is for
  canonical diffs only.
- Replacing the existing `kubectl` or Kubernetes MCP servers.
- Changing Talos, Cilium, Omni, nodes, taints, or other substrate configuration.

## Evidence and Provenance

The selected chart artifact is:

| Item | Selected value |
|---|---|
| Helm repository | `https://skyhook-io.github.io/helm-charts` |
| Chart | `radar` |
| Chart version | `1.10.0` |
| App version | `1.10.0` |
| Package SHA-256 | `4b463be043617bc235f30eff79d59e7e3b5799e6e9a6d454b2b6bffce47d5e58` |

The package was downloaded and inspected on 2026-08-16. Its packaged
`Chart.yaml`, `values.yaml`, and templates agree on the values used below. The
digest is a review receipt, not an integrity pin enforced by ArgoCD; re-download
and compare it before implementation. Stop if the same version resolves to a
different artifact.

The same-day pre-deployment cluster observation found no `metrics.k8s.io`,
custom metrics, or external metrics APIService and no Prometheus,
VictoriaMetrics, OpenCost, or Hubble Relay workload. Radar's core resource,
topology, issue, timeline, and MCP functions do not depend on those services.
CPU/memory widgets, PromQL, cost, traffic, and rightsizing will remain absent or
degraded until their respective dependencies are added separately.

Radar chart `1.10.0` exposes `argocd.existingSecret`,
`argocd.existingSecretKey`, `argocd.url`, and `argocd.insecureTls`. The chart
renders the selected Secret key as `RADAR_ARGOCD_TOKEN`; it does not place the
token value in Helm release state. Radar reads environment-managed integration
settings at startup, makes the Settings card read-only, and requires a pod
restart after token rotation.

The same-day live ArgoCD observation found chart `7.9.1`, Service
`argocd-ha-helm-server.argocd.svc.cluster.local`, and `server.insecure: true`.
The selected internal endpoint is therefore plain HTTP. TLS verification must
remain enabled for any future HTTPS endpoint; the current HTTP endpoint does
not require the insecure-TLS exception.

The live Tailscale Operator currently labels ingress proxy pods with:

```yaml
tailscale.com/managed: "true"
tailscale.com/parent-resource: <ingress-name>
tailscale.com/parent-resource-ns: <ingress-namespace>
tailscale.com/parent-resource-type: ingress
```

It also adds an `app` label whose value is a generated UUID. The UUID is not a
stable identity and must not be committed into a NetworkPolicy. Reverify the
stable labels immediately before implementation because operator-generated
metadata can change across upgrades.

## Selected Architecture

```mermaid
flowchart LR
    OP["Operator or MCP client on tailnet"] -->|"Tailscale identity and TLS"| TS["Tailscale Ingress proxy"]
    TS -->|"NetworkPolicy allow on TCP 9280"| RD["Radar pod and ClusterIP"]
    RD -->|"Read-only ServiceAccount"| API["Kubernetes API"]
    RD -->|"Get-only API token over cluster HTTP"| ARGO["ArgoCD API server"]
    INF["Infisical /radar"] --> ESO["External Secrets Operator"]
    ESO --> SEC["radar-argocd-token Secret"]
    SEC --> RD
    RD -->|"SQLite"| PVC["1 GiB Longhorn PVC"]
    KP["Ordinary cluster pod"] -. "NetworkPolicy deny" .-> RD
```

Radar runs as one replica in namespace `radar`. The chart creates the
Deployment, ClusterIP Service, ServiceAccount, read-only ClusterRole and
ClusterRoleBinding, and PVC. This repository creates the Tailscale Ingress and
NetworkPolicy locally so their behavior remains explicit and reviewable.

The root Application is named `radar`, so the nested chart Application must be
named `radar-helm`. Set `spec.source.helm.releaseName: radar` explicitly on the
child. Without that override, ArgoCD would use `radar-helm` as the Helm release
name and the rendered Service, PVC, and instance label would not match the
Ingress and NetworkPolicy contract below.

The root Application is assigned wave 6, after Tailscale and Longhorn. Inside
the Radar directory:

| Sub-wave | Resource | Reason |
|---|---|---|
| 0 | NetworkPolicy and ExternalSecret | Establish the ClusterIP boundary and materialize the token before a Radar pod exists |
| 1 | `radar-helm` child Application | Install the exact-pinned chart |
| 2 | Tailscale Ingress | Expose the healthy Service to the tailnet |

Wave 6 may run alongside Netdata because Radar does not depend on Netdata.

## Helm Configuration Contract

The implementation must express the following selected values explicitly even
when they match chart defaults. Explicit security and persistence choices make
future chart-default changes visible in review.

```yaml
replicaCount: 1

service:
  type: ClusterIP
  port: 9280

ingress:
  enabled: false

httpRoute:
  enabled: false

auth:
  mode: none

cloud:
  enabled: false

mcp:
  enabled: true

argocd:
  existingSecret: radar-argocd-token
  existingSecretKey: token
  url: http://argocd-ha-helm-server.argocd.svc.cluster.local
  insecureTls: false

rbac:
  create: true
  helm: false
  secrets: false
  viewRBAC: false
  viewWebhooks: false
  podExec: false
  podLogs: true
  portForward: false
  selfUpgrade: false
  traffic: false
  metrics: false

timeline:
  storage: sqlite
  retention: 168h
  maxSize: 800Mi

persistence:
  enabled: true
  storageClassName: longhorn-standard
  accessMode: ReadWriteOnce
  size: 1Gi
```

Keep the chart's default resource requests and limits unless render or runtime
evidence shows they are unsuitable. Do not copy the chart's full CRD-group map
into this repository: the chart-managed read-only defaults cover ArgoCD,
Cilium, External Secrets, and other supported CRDs, and unused API groups are a
no-op when their CRDs are absent.

SQLite plus a ReadWriteOnce PVC causes chart 1.10.0 to render a `Recreate`
Deployment strategy and reject multiple replicas. `timeline.maxSize` remains
below the PVC size so Radar can prune before the volume fills.
`longhorn-standard` assigns the repository's weekly, four-week backup tier for
replaceable data.

## Access and Authorization Boundary

The local Ingress must use `ingressClassName: tailscale`, send `/` to Service
`radar` on port `9280`, and request the Tailscale hostname `radar`. The expected
tailnet endpoints are:

- UI: `https://radar.tailfb3ea.ts.net/`
- MCP: `https://radar.tailfb3ea.ts.net/mcp`

Radar deliberately runs with `auth.mode: none`. This is an explicit
single-operator homelab exception to Radar's upstream recommendation to enable
authentication for an ingress-exposed installation. Tailscale device/user
authorization and tailnet TLS are the external access control. Radar does not
receive a distinct Kubernetes identity for the human or MCP client, and every
request shares the pod ServiceAccount's permissions.

No User or Group RoleBinding is required. Kubernetes RBAC still matters because
it defines the maximum capability of the Radar process and every MCP caller.
Radar advertises both read and write MCP tools, but the selected ServiceAccount
cannot perform the write operations. If `rbac.helm`, `rbac.podExec`,
`rbac.portForward`, Secrets, node operations, or additional write rules are
enabled later, the MCP boundary changes and requires a separate reviewed
change.

Pod-log access is intentionally retained. Logs can contain application data
despite Radar's documented redaction, so Tailscale access to Radar also implies
access to every log the ServiceAccount may read. The operator accepts that
tradeoff for this homelab.

### ArgoCD API Boundary

The ArgoCD Helm values define a local account with only the `apiKey`
capability:

```yaml
configs:
  cm:
    accounts.radar: apiKey
  rbac:
    policy.csv: |
      p, role:radar, applications, get, */*, allow
      g, radar, role:radar
```

This permits Radar to request ArgoCD's canonical rendered Application diff and
nothing else. It does not grant `sync`, `update`, `delete`, `action`, or
`override`. The ArgoCD token is a separate authorization boundary from Radar's
Kubernetes ServiceAccount: neither credential expands the other.

The non-expiring token is dedicated to this one in-cluster consumer and is
stored at `/radar/ARGOCD_TOKEN` in the `mothership-s0-ew` Infisical project,
`prod` environment. ESO materializes only a `token` key in Secret
`radar/radar-argocd-token`. No token value may appear in Git, Helm values,
command output, runtime evidence, or documentation.

The endpoint is pinned to
`http://argocd-ha-helm-server.argocd.svc.cluster.local`; do not use the
Tailscale ingress from inside the cluster. Rotation means minting a replacement
token, updating Infisical, waiting for ESO to refresh, and rolling the Radar
Deployment so its environment is re-read. Revoke the old token only after the
replacement connection is verified.

## NetworkPolicy Contract

The policy selects only the Radar workload:

```yaml
podSelector:
  matchLabels:
    app.kubernetes.io/name: radar
    app.kubernetes.io/instance: radar
```

It permits ingress only on TCP `9280` from one peer that combines the namespace
and pod selectors below. They must be fields of the same `from` item so
Kubernetes evaluates them as AND, not as two independently allowed sources.

```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: tailscale-operator
        podSelector:
          matchLabels:
            tailscale.com/managed: "true"
            tailscale.com/parent-resource: radar
            tailscale.com/parent-resource-ns: radar
            tailscale.com/parent-resource-type: ingress
    ports:
      - protocol: TCP
        port: 9280
```

Do not allow the entire `tailscale-operator` namespace and do not select the
generated `app` UUID. Do not add an ingress exception for ordinary namespaces,
monitoring pods, or all nodes without a reproduced failing path. The policy
does not restrict egress; Radar still needs the Kubernetes API and may perform
its documented anonymous version check.

The policy is fail-closed for cluster bypass: a wrong proxy selector makes the
UI unavailable rather than exposing the ClusterIP. If chart probes fail under
Cilium, capture the denied source and review the narrowest required exception
instead of guessing one in advance.

## MCP Operating Model

The personal MCP client configuration is workstation state and does not belong
in this GitOps repository. After the HTTPS endpoint is validated, the operator
may add a remote HTTP MCP server named `radar` with this URL:

```toml
[mcp_servers.radar]
url = "https://radar.tailfb3ea.ts.net/mcp"
```

Radar MCP is complementary to the existing Kubernetes MCP tools:

- Use Radar for curated issues, topology and neighborhood relationships,
  deduplicated events, change history, resource context, and filtered logs.
- Use `kubectl` or the Kubernetes MCP path for exact raw API inspection and
  operations Radar does not expose.

The personal client configuration is not part of deployment completion. The
server must be healthy and its read-only RBAC boundary proven before a client
is connected.

## Repository Change Set

The ArgoCD deep-diff extension creates or updates only these concerns:

| File | Intended change |
|---|---|
| `apps/argocd/ha-upgrade.yaml` | API-only `radar` account and get-only Application policy |
| `apps/external-secrets/clustersecretstore.yaml` | Infisical `/radar` ClusterSecretStore |
| `apps/radar/externalsecret.yaml` | Token projection into `radar-argocd-token` |
| `apps/radar/application.yaml` | Existing Secret reference and pinned in-cluster endpoint |
| `apps/root.yaml` | ESO default-field ignore rules and `RespectIgnoreDifferences=true` |
| `docs/adding-applications.md` | `/radar` secret-store inventory |
| `docs/architecture.md` | ArgoCD token and authorization boundary |
| `specs/radar-in-cluster.md` | Selected design, rollout gates, and runtime evidence |

No Secret value, new human RoleBinding, or MCP client configuration belongs in
this repository.

## ArgoCD Integration Sequence

1. Re-check Radar chart `1.10.0` and ArgoCD chart `7.9.1` value keys against
   their actual `values.yaml` files.
2. Add the API-only account and get-only Application policy to the nested
   ArgoCD Helm values. Render and validate the generated ConfigMaps.
3. Publish the account change as an atomic commit. Because both `argocd-ha` and
   `argocd-ha-helm` are manual-sync safety gates, inspect all pre-existing
   drift before explicitly syncing both stages.
4. After the account is live, mint one non-expiring token with ID
   `radar-in-cluster`. Never print or persist it outside the direct transfer to
   Infisical.
5. Create `/radar/ARGOCD_TOKEN` in Infisical, then add the ClusterSecretStore,
   ExternalSecret, Radar Helm values, parent ignore rules, and documentation.
6. Render and validate the Radar Deployment's Secret reference and URL without
   resolving or printing the Secret value.
7. Publish the integration as a second atomic commit. Let the normal automated
   policy reconcile `root`, parent `radar`, and child `radar-helm`.
8. Verify the ExternalSecret, Secret metadata, Deployment rollout, Radar
   integration status, canonical deep diff, and get-only ArgoCD permissions.
9. Record dated runtime evidence and fresh local/remote SHA equality.

## Verification and Acceptance Criteria

Before publication:

- `helm template` for chart `1.10.0` renders one Deployment, one ClusterIP
  Service on `9280`, one PVC, chart-managed RBAC, and no chart Ingress or
  HTTPRoute.
- The Deployment renders `Recreate`, one replica, the SQLite arguments, the
  `/data` volume, and the chart's restricted container security context.
- The rendered ClusterRole has no Secret read, wildcard writes, pod exec,
  port-forward, or node mutation permissions; pod-log reads are present.
- The local NetworkPolicy selects the rendered Radar pod labels and only the
  observed stable Tailscale ingress proxy labels.
- The ArgoCD chart renders `accounts.radar: apiKey` and only the selected
  Application `get` policy.
- The Radar chart renders a `secretKeyRef` to `radar-argocd-token/token`, the
  pinned HTTP endpoint, and `insecureTls: false`; no token value is rendered.
- Client-side schema validation accepts all local resources. Server-side
  dry-run validates the ArgoCD Applications in the existing `argocd` namespace;
  do not create the future `radar` namespace imperatively just to dry-run its
  Ingress and NetworkPolicy.
- `pre-commit run --files <exact changed files>` and `git diff --check` pass.

After ArgoCD reconciliation:

1. Parent `radar` and child `radar-helm` Applications are `Synced` and
   `Healthy`.
2. The Radar pod is ready, the `radar` PVC is `Bound` to
   `longhorn-standard`, and diagnostics report SQLite storage with the selected
   retention and size bounds.
3. `https://radar.tailfb3ea.ts.net/` loads from an authorized tailnet client.
4. The MCP endpoint completes initialization and tool listing, and a read-only
   call such as `get_dashboard` succeeds.
5. A non-matching ordinary pod cannot connect to `radar.radar.svc:9280`, while
   the Tailscale ingress proxy can.
6. ServiceAccount authorization checks prove `get pods/log` is allowed and
   `get secrets`, `create deployments`, `patch deployments`, pod exec, and
   port-forward are denied.
7. Missing metrics, cost, rightsizing, and traffic integrations degrade
   honestly without making the core UI or MCP server unhealthy.
8. After the first normal chart rollout or pod replacement, timeline events
   from before the restart remain available. Do not force an imperative restart
   solely to satisfy this check.
9. ArgoCD reports account `radar` with API-key capability. Its token can get
   Applications and cannot sync, update, delete, or invoke actions.
10. ExternalSecret `radar-argocd-token` is Ready, its target Secret exists with
    key name `token`, and no validation output contains the value.
11. Radar reports the ArgoCD integration connected to the pinned in-cluster
    endpoint after the Secret-backed rollout.
12. An Application Changes view returns the canonical ArgoCD-rendered diff or
    a confirmed no-drift result rather than the annotation-only fallback.

Record runtime results as dated evidence. ArgoCD health proves reconciliation,
not the Tailscale, NetworkPolicy, RBAC, MCP, or persistence boundaries by
itself.

### Runtime Evidence — 2026-08-16

- Git commit `0655de3709cdf7042646e17bc7e89b05bc3353fa` was pushed to
  `origin/main`, and the local and remote SHAs matched after a fresh fetch.
- ArgoCD reconciled `root` and parent `radar` at that commit; both were
  `Synced` and `Healthy`. Child `radar-helm` was `Synced` and `Healthy` at chart
  revision `1.10.0`.
- The Radar Deployment rolled out one ready pod with the `Recreate` strategy.
  PVC `radar` was `Bound` as `1Gi` `ReadWriteOnce` on
  `longhorn-standard`; its Longhorn volume was attached and healthy.
- `https://radar.tailfb3ea.ts.net/` returned HTTP 200 through the
  operator-created `ts-radar-*` proxy. The live proxy carried all four stable
  labels selected by the NetworkPolicy. A request from an ordinary Netdata pod
  to `radar.radar.svc.cluster.local:9280` timed out, proving the ClusterIP
  bypass was denied while the Tailscale path remained available.
- `/api/health` returned HTTP 200 with status `healthy`. `/api/diagnostics`
  reported Radar `1.10.0`, `timeline.storageType: sqlite`, retention `168h`,
  maximum storage `838860800` bytes, a present event store, and zero store
  errors.
- MCP initialization negotiated protocol `2025-06-18` with server version
  `1.10.0`; `tools/list` returned 28 tools. Read-only `get_dashboard` and
  `get_pod_logs` calls both succeeded.
- ServiceAccount checks used a short-lived `radar` token directly against a
  port-forwarded API server. Pod and pod-log reads were allowed; Secret and
  metrics reads, Deployment create and patch, Pod delete, exec, and
  port-forward were denied. This direct-token method was necessary because
  `kubectl auth can-i --as=...` through the Tailscale API proxy returned the
  caller's broader authority and was not valid evidence for the pod identity.
- Metrics collection reported Kubernetes `403` responses and Prometheus was
  disconnected, while the UI, MCP server, cache, timeline, and ArgoCD health
  remained available as designed.
- The Secret-backed ArgoCD rollout performed the first normal chart-driven pod
  replacement at `2026-08-16T09:11:49Z`. After the replacement, Radar MCP
  returned 42 retained changes timestamped before the new pod, including the
  `argocd-cm` and `argocd-rbac-cm` changes from `09:04:28Z`. This closes the
  cross-restart SQLite retention criterion without an imperative test restart.

### ArgoCD Deep-Diff Runtime Evidence — 2026-08-16

- Commit `a6e1d90a33ab61c4d7acf9c752d77b5c1ed27472` added the API-only
  account and get-only policy. Commit
  `c5d40f9fb2797435b14b09c6f059b8f84c7dad16` added the Infisical, ESO,
  and Secret-backed Radar configuration. Each commit was pushed to `main`,
  followed by a fresh fetch proving local and remote SHA equality.
- Parent `argocd-ha` was manually synced at the account commit. The nested
  `argocd-ha-helm` Application already had unrelated Deployment, StatefulSet,
  and hook drift, so only ConfigMaps `argocd-cm` and `argocd-rbac-cm` were
  selectively dry-run and synced. The account change did not roll or reconcile
  the pre-existing HA workload drift; the child remains `Healthy` and
  `OutOfSync` for that separate concern.
- Live ArgoCD reports account `radar` enabled with only the `apiKey`
  capability and one non-expiring token ID, `radar-in-cluster`. Policy checks
  returned `Yes` only for Application `get`; `sync`, `update`, `delete`,
  `action`, and `override` each returned `No`.
- Infisical contains key name `ARGOCD_TOKEN` under `/radar`. The token value
  was transferred directly without entering Git, a file, Helm state, command
  output, or runtime evidence. ClusterSecretStore `infisical-radar` reported
  `Ready=True` with `store validated`; ExternalSecret `radar-argocd-token`
  reported `Ready=True` with `secret synced`; the resulting Opaque Secret had
  only key name `token` and an ExternalSecret owner reference.
- Root, `external-secrets`, parent `radar`, and child `radar-helm` Applications
  reconciled `Synced` and `Healthy`. Radar Deployment generation 2 became ready
  with one replica and no restarts. Its pod template references
  `radar-argocd-token/token` for `RADAR_ARGOCD_TOKEN` and pins
  `RADAR_ARGOCD_URL` to the selected cluster Service.
- Radar `/api/config` reported `argoCdEnvManaged: true` and
  `argoCdTokenSet: true`; `/api/integrations/argocd/status` reported
  `configured: true`, `connected: true`, and the selected internal address.
  Logs confirmed the environment-provisioned integration is read-only in
  Settings.
- A resource diff for NetworkPolicy `radar/radar-ingress` returned source
  `argocd-api`, non-empty Git-rendered desired and normalized live manifests,
  and zero field drift. This proves the canonical ArgoCD API path rather than
  the annotation-only fallback.

## Upgrade and Renovate Policy

`targetRevision` is exactly `1.10.0`. A Radar-specific Renovate rule must set
`automerge: false` for package `radar` at every update level. This override is
deliberate even though the repository generally auto-merges chart patches:
Radar's chart couples UI behavior, MCP tool surface, ClusterRole generation,
and storage migrations, so every version requires a rendered RBAC and values
review before merge.

## Failure Handling and Rollback

- If a chart update fails but the current release is healthy, revert only the
  chart-version change so the PVC remains attached to the application.
- If the Tailscale path fails, inspect Ingress status, operator proxy labels,
  and NetworkPolicy denies. Fix Git and let ArgoCD converge; do not patch a
  broad live allow rule.
- If SQLite fails, inspect the PVC, mount, file permissions, and diagnostics.
  Do not fall back to memory silently because that violates the persistence
  decision.
- Removing the entire Radar Application under automated prune can delete its
  PVC. The timeline is classified as replaceable `longhorn-standard` data, but
  preserve a backup first if its history matters at removal time.
- If resolution requires a Cilium, Talos, Omni, node, taint, or machine-class
  change, stop and hand the substrate concern to `../Omni-Scale`.

## Deferred Follow-Up

Each of these is a separate decision and change:

- Add metrics-server for live CPU and memory widgets.
- Add Prometheus or VictoriaMetrics for PromQL and historical metrics.
- Add OpenCost for cost views.
- Add Hubble Relay or another supported source for traffic views.
- Enable Radar RBAC-object visibility, Secrets, or any write capability.
- Add OIDC or proxy auth if the user population grows beyond the single
  operator or the Tailscale trust boundary changes.

## References

- [Radar in-cluster deployment](https://radarhq.io/docs/configuration/in-cluster)
- [Radar MCP documentation](https://radarhq.io/docs/features/mcp)
- [Radar GitOps and ArgoCD integration](https://github.com/skyhook-io/radar/blob/v1.10.0/docs/gitops.md)
- [Radar chart 1.10.0 release](https://github.com/skyhook-io/helm-charts/releases/tag/radar-1.10.0)
- [Radar chart values](https://github.com/skyhook-io/helm-charts/blob/main/charts/radar/values.yaml)
- [ArgoCD local accounts](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)
- [ArgoCD RBAC](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
- [`docs/adding-applications.md`](../docs/adding-applications.md)
- [`docs/architecture.md`](../docs/architecture.md)
- [`docs/tailscale-networking.md`](../docs/tailscale-networking.md)
- [`docs/backup-storage.md`](../docs/backup-storage.md)
