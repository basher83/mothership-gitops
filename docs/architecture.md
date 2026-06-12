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
Wave 2:  External Secrets Operator (CRDs + controller)
Wave 3:  ClusterSecretStores (Infisical connection)
Wave 4:  Tailscale Operator + ArgoCD Ingress
          - sub-wave 0: DNSConfig (nameserver for ts.net resolution)
          - sub-wave 1: tailscale-operator-helm
          - sub-wave 5: coredns-tailscale (SSA patch for ts.net forwarding)
Wave 5:  Longhorn (storage) + Longhorn Ingress
Wave 6:  Netdata (monitoring)
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
| `coredns-tailscale` | `prune: false`, `selfHeal: true` | ConfigMap must survive app removal; self-heal restores ts.net forwarding after Talos lifecycle events overwrite CoreDNS |

## Network Exposure

All web UIs are exposed via Tailscale Ingress only — no public exposure.
See `tailscale-networking.md` for ingress and egress patterns.

## Repo Boundary

This repo owns everything ArgoCD reconciles onto the cluster. The Talos/Omni
substrate (cluster templates, machine classes, SideroLink, Cilium MTU
rationale) is owned by [Omni-Scale](https://github.com/basher83/Omni-Scale).
