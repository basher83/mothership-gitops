# Architecture

How ArgoCD reconciles `talos-prod-01` after bootstrap. For bootstrap commands
see `README.md`. For adding applications see `adding-applications.md`.

## App of Apps

`bootstrap/bootstrap.yaml` installs the root Application, which points at
`apps/`. The root Application discovers all YAML under `apps/` — both
directories referenced by Application manifests in `root.yaml` and standalone
single-file Applications (e.g. `apps/anthropic-oauth-proxy.yaml`).

## Sync Waves

```text
Prereq:  Cilium CNI, External Secrets Operator, Longhorn, ArgoCD non-HA (Helm, see README)
Wave 2:  External Secrets stack
          - sub-wave 1: external-secrets-helm (CRDs + controller)
          - sub-wave 2: ClusterSecretStores (Infisical connection)
Wave 4:  Tailscale Operator + ArgoCD Ingress
          - sub-wave 0: DNSConfig (nameserver for ts.net resolution)
          - sub-wave 1: tailscale-operator-helm
          - sub-wave 5: coredns-tailscale (SSA patch for ts.net forwarding)
Wave 5:  Longhorn (storage) + Longhorn Ingress
Wave 6:  Netdata (monitoring) + Radar (Kubernetes UI and MCP)
Wave 7:  Homarr (dashboard)
Wave 8:  Anthropic OAuth Proxy (Kustomize from tailnet-microservices)
Wave 9:  Phoenix (LLM observability eval backend)
Wave 99: ArgoCD HA upgrade (manual sync)
```

Within a wave, ExternalSecrets use `sync-wave: "0"` so secrets exist before
the app that consumes them.

## Sync Policy Exceptions

Default policy is automated sync with `prune: true` and `selfHeal: true`,
plus `ServerSideApply=true`. Deviations are deliberate:

| Application | Deviation | Reason |
|---|---|---|
| `argocd-ha` (wave 99) | No automated sync | Safety gate — HA upgrade is triggered manually after Longhorn is healthy |
| `argocd-ha-helm` (nested) | No automated sync | Same safety gate, second stage |
| `longhorn` | `prune: false` | Pruning storage resources risks data deletion |
| `longhorn-helm` (nested) | `prune: false` | Chart-owned CRDs and controllers — a chart revision that stops rendering a CRD would make it prune-eligible, and CRD deletion removes all CRs stored under it, taking down the storage control plane |
| `coredns-tailscale` | `prune: false`, `selfHeal: true` | ConfigMap must survive app removal; self-heal restores ts.net forwarding after Talos lifecycle events overwrite CoreDNS |
| `anthropic-oauth-proxy` | No automated sync | Cross-repo promotion gate — the app tracks `tailnet-microservices` `main`, whose CI does not gate manifest validity (bot tag-bump commits carry `[skip ci]`, and the manifests job does not block deploy). Manual sync is the deliberate promotion step; revisit an exact SHA pin once the proxy's refactor churn settles |

## Chart Versioning

Every chart Application is exact-pinned. Version bumps arrive as Renovate PRs
via the `argocd` manager (`renovate.json`), and `rangeStrategy: pin` re-pins
any range that slips in. The update policy varies by chart:

| Charts | Patch | Minor | Major |
|--------|-------|-------|-------|
| `homarr`, `netdata`, `tailscale-operator` | Auto-merge after 3 days | Auto-merge after 3 days, own group | Dashboard approval |
| `phoenix` | Auto-merge | Monday review group | Dashboard approval |
| `radar` | Review | Monday review group | Dashboard approval |
| `longhorn`, `external-secrets` | Review | Monday review group | Dashboard approval |
| `argo-cd` | Review | Monday review group | Dashboard approval |

The substrate pair never auto-merges because everything else transitively
depends on storage and secrets. Radar never auto-merges because its chart
couples the UI, MCP tool surface, generated ClusterRole, and SQLite storage
behavior. The three formerly floating charts auto-merge minors in a separate
group because Renovate only auto-merges a grouped PR when every update in it is
auto-mergeable, so a pending reviewed minor would otherwise block them.

For auto-synced Applications, merging the PR is the promotion step. `argo-cd`
is the exception: merging only updates Git, and the cluster changes when the
manual `argocd-ha` and `argocd-ha-helm` gates are synced. It therefore never
auto-merges, so Git cannot silently run ahead of the gate.

Renovate automerge relies on the repository-owned `Fast Gate` workflow. Its
`mise run ci` task preserves the pre-commit hygiene and YAML checks, validates
the Renovate and GitHub Actions schemas, then renders every exact-pinned Helm
Application with its committed values and validates rendered built-in
Kubernetes resources with kubeconform. The workflow runs on `renovate/**`
branch pushes so the inherited `prCreation: not-pending` policy receives a
repository-owned result before Renovate creates a PR. The render is
cluster-independent: it does not prove CRD semantics, admission behavior,
Argo reconciliation, or live runtime health. Floating chart revisions are
intentionally reported and skipped because re-resolving them would make an
unrelated pull request test a different desired version.

`tailscale-operator`, `netdata`, `homarr`, and `argo-cd` floated on
major-version wildcards until 2026-11-07. Renovate cannot bump a wildcard, so
they upgraded unattended within their major. They were pinned to the versions
live at commit time so the cluster did not change. Pinning below the live
version would request a downgrade (see the Longhorn entry in
`troubleshooting.md`).

## Network Exposure

All web UIs are exposed via Tailscale Ingress only — no public exposure.
See `tailscale-networking.md` for ingress and egress patterns.

Radar is a deliberate single-operator exception to application-level ingress
authentication. Its UI and MCP endpoint share the `radar` Tailscale hostname
and the chart ServiceAccount: pod logs and cluster resource reads are enabled,
while Secrets, Helm writes, pod exec, port-forward, and node mutations are not.
A NetworkPolicy admits the ClusterIP only from the operator-created Radar
Ingress proxy, preventing ordinary pods from bypassing Tailscale. The selected
chart, storage, access, upgrade, and validation contract is recorded in
[`../specs/radar-in-cluster.md`](../specs/radar-in-cluster.md).

Radar's canonical Git-rendered diffs use a separate ArgoCD local account with
only `applications get`. Its dedicated token flows from Infisical `/radar`
through ESO into the Radar Deployment and is pinned to the plain-HTTP
`argocd-ha-helm-server` cluster Service. The token grants no sync or mutation
authority and does not expand the chart ServiceAccount. Account and policy
changes inherit the manual `argocd-ha` and `argocd-ha-helm` promotion gates;
the Secret-backed Radar configuration follows Radar's normal automated sync.

Tailscale exposure does not make every cluster-internal route authorized. For
the credential-backed `anthropic-oauth-proxy`, tailnet membership is the
intended main-proxy boundary, while kubeconfig and Kubernetes RBAC through
port-forwarding are the intended admin boundary. The current source manifests
do not yet enforce those boundaries against ordinary cluster pods. The
selected design, evidence classification, cross-repository ownership, and
rollout gates are recorded in
[`../specs/oauth-proxy-boundary-remediation.md`](../specs/oauth-proxy-boundary-remediation.md).
This is planned work and must not be read as a claim that the findings are
remediated.

## Architecture Decisions

Consequential platform choices and their supersession history live in the
[ADR library](adrs/README.md). The active decision to keep the Tailscale API
server proxy as a standing secondary `kubectl` path is recorded in
[ADR-002](adrs/ADR-002-enable-tailscale-api-server-proxy.md).

## Repo Boundary

This repo owns everything ArgoCD reconciles onto the cluster. The Talos/Omni
substrate (cluster templates, machine classes, SideroLink, Cilium MTU
rationale) is owned by [Omni-Scale](https://github.com/basher83/Omni-Scale).
