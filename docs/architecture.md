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

Substrate charts are exact-pinned: `longhorn-helm` and `external-secrets-helm`
(everything else transitively depends on storage and secrets), plus `phoenix`
(pinned after the 5.0.23 -> 9.0.3 upgrade churn) and `radar`. Version bumps for
pinned charts arrive as Renovate PRs via the `argocd` manager
(`renovate.json`): patches auto-merge except for the substrate pair and Radar,
minors group for Monday review, and majors require dependency-dashboard
approval. Radar never auto-merges at any update level because its chart couples
the UI, MCP tool surface, generated ClusterRole, and SQLite storage behavior.
Merging the PR is the promotion step.

Remaining charts (`tailscale-operator`, `netdata`, `homarr`, `argo-cd`) still
float on major-version wildcards — Renovate cannot bump a wildcard, so they
upgrade unattended within their major. Pin them to opt into PR-gated upgrades.

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
