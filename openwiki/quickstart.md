---
type: orientation
title: "Mothership GitOps: orientation and task routing"
description: "Start here to identify ownership, authoritative entrypoints, and the safest route to inspect or change applications on talos-prod-01. Routes application, integration, recovery, and validation tasks to focused guides."
tags: [gitops, orientation, argocd, task-routing]
verified:
  - by: openwiki/0.9.0
    at: 2026-11-11T09:22:19.403Z
sources:
  - id: openwiki-source-8037e2358a2c4f9b2c722a11
    resource: repo://AGENTS.md
  - id: openwiki-source-8223aa7ee93a67a7e22499e2
    resource: repo://apps/root.yaml
  - id: openwiki-source-0c9c49dabff608a7c4bfef1c
    resource: repo://bootstrap/bootstrap.yaml
  - id: openwiki-source-84d4c5fec7272d14cce2d242
    resource: repo://docs/adding-applications.md
  - id: openwiki-source-115b2dad781e2a2c5b5a980d
    resource: repo://docs/architecture.md
  - id: openwiki-source-84aa6f5274f89a06259b8344
    resource: repo://docs/argocd-cli.md
  - id: openwiki-source-72b5d686f860ea86c8592080
    resource: repo://mise.toml
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
  - id: openwiki-source-8175f678b4142601a495a04e
    resource: repo://scripts/validate-gitops.sh
generated: { by: "openwiki/0.9.0", at: "2026-11-11T09:22:19.403Z" }
---

# Mothership GitOps: orientation and task routing

Mothership GitOps answers **what runs on `talos-prod-01` after the Omni-managed Talos substrate exists**. It owns ArgoCD reconciliation, application manifests, ingress, secrets wiring, Longhorn configuration and backups, monitoring, and dashboards—not cluster provisioning.

**Stop at the substrate boundary.** Cluster templates, machine classes, node requirements, SideroLink, and the rationale for Cilium MTU constraints belong to `../Omni-Scale` ([upstream repository](https://github.com/basher83/Omni-Scale)). If a fix requires node capacity, taints, or machine-class changes, route it there rather than compensating with manifest hacks here. See the [repository boundary](../README.md#repo-boundary).

## Start with the right authority

- **Working rules:** [AGENTS.md](../AGENTS.md) governs changes and wins if another document contradicts it. Durable operational knowledge belongs in the matching source document under `docs/`.
- **Installation and rebuilds:** [README bootstrap](../README.md#bootstrap) and [recovery](../README.md#recovery) are the command authority. Follow them directly; this page does not maintain a second bootstrap recipe. Applying the bootstrap manifest alone is not a complete cluster installation: prerequisite CNI, ESO, Longhorn, and non-HA ArgoCD installation comes first.
- **Reconciliation entrypoint:** [bootstrap/bootstrap.yaml](../bootstrap/bootstrap.yaml) creates the `root` Application in `argocd`, tracking this repository's `main` branch at `apps/`. [apps/root.yaml](../apps/root.yaml) declares the wave-ordered platform Applications; standalone Application YAML in `apps/` is also discovered. This is an App of Apps graph, not one flat Helm release.
- **Local checks:** [mise.toml](../mise.toml) pins the validation toolchain and defines the hygiene, GitOps validation, and combined CI tasks. The operator `argocd` CLI is installed separately through Homebrew; use the [CLI guide](../docs/argocd-cli.md) for context setup and access modes.

## Route by task

| What you need to do | Start here | Why this route matters |
|---|---|---|
| Understand sync order, drift, deletion, or a parent/child Application | [Reconciliation and promotion boundaries](architecture/reconciliation.md) | Establish which Application owns the change and whether sync is automated or gated. |
| Add an app, change Helm values, upgrade, or promote a revision | [Application change workflow](workflows/application-changes.md) | Follow layout, dependency, exact-version, validation, and promotion rules together. |
| Inspect a failing app, bootstrap, or recover a cluster | [Bootstrap and triage](operations/bootstrap-and-triage.md) | Start with diagnostics and the authoritative README procedure rather than ad hoc live mutations. |
| Check what local or CI validation proves | [Validation gates](testing/validation-gates.md) | Separate rendering and schema checks from live reconciliation and runtime verification. |
| Wire credentials or diagnose ExternalSecret drift | [Infisical and External Secrets](integrations/secrets.md) | Follow the credential ownership chain and controller-default handling. |
| Expose a UI, reach a tailnet service, or diagnose DNS/access | [Tailnet networking](integrations/tailscale-networking.md) | Distinguish ingress, egress, operator mutations, and cluster-internal access boundaries. |
| Change Radar UI, MCP, or ArgoCD diff access | [Radar integration](integrations/radar.md) | Review its API authorities, access restrictions, persistence, and validation contract. |
| Change Homarr, Netdata, Phoenix, or proxy configuration | [Workload contracts](architecture/workload-services.md) | Check application-specific coupling and the proxy's external ownership. |
| Change PVCs, backup tiers, storage versions, or restore data | [Storage and backups](operations/storage-and-backups.md) | Review persistence and deletion hazards before changing storage resources. |

For original policy and historical rationale, consult [source architecture](../docs/architecture.md), [architecture decisions](../docs/adrs/README.md), and [incident reports](../docs/incidents/README.md). The wiki routes and explains; repository manifests, scripts, and source documents remain authoritative.

## Shortest safe path

### Inspect without promoting

1. Confirm the target kubeconfig and ArgoCD contexts before inspecting `talos-prod-01`. Use the [CLI guide](../docs/argocd-cli.md): **core mode uses Kubernetes identity and bypasses ArgoCD API RBAC**, while server mode authenticates to ArgoCD and follows its accounts and policies. They are not equivalent permission boundaries.
2. Identify the owning parent and, where present, nested chart Application. Read its source, sync policy, and dependencies through the [reconciliation guide](architecture/reconciliation.md); use [triage](operations/bootstrap-and-triage.md) for symptoms.
3. Treat sync as promotion, not inspection. Most Applications automatically prune and self-heal. Exceptions are deliberate: `argocd-ha` and `argocd-ha-helm` are both manual gates; `anthropic-oauth-proxy` has a manual cross-repository gate. Do not enable prune on `longhorn`, `longhorn-helm`, or `coredns-tailscale`.

### Change with a bounded rollout

1. Follow the [application workflow](workflows/application-changes.md) and [source checklist](../docs/adding-applications.md). New apps need a documented wave; chart versions must be exact-pinned, and value keys must be checked against the chart's actual `values.yaml`.
2. Preserve the integration invariants: web UIs require Tailscale Ingress, with no public exposure; secrets flow **Infisical → ESO → Secret**, never committed values. The ESO bootstrap credential is the only manually created secret. Use the integration guides before changing either boundary.
3. Prefer Git changes to live `kubectl` mutations. Break-glass fixes must follow documented procedures and leave Git convergent. Keep one concern per commit and update the matching source documentation when the change introduces a gotcha or operational caveat.
4. Run `pre-commit run --files <changed>` before committing. Use `mise run validate:gitops` for exact-pinned Helm rendering and Kubernetes schema validation, or `mise run ci` for the combined hygiene and GitOps gate. See [validation gates](testing/validation-gates.md) for scope: a passing local render does **not** prove CRD semantics, admission behavior, ArgoCD reconciliation, or runtime health.
5. Review promotion before merging: for auto-synced apps, merging is promotion. ArgoCD HA and the external proxy retain their manual gates. Plan live verification and storage recovery as appropriate rather than interpreting CI success as rollout success.
