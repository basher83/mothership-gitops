# Spec: Operator Migration — GitOps (Spec B)

**Status:** Implemented handoff record; live validation pending
**Created:** 2026-02-07
**Author:** Brent + Claude
**Scope:** mothership-gitops repo only

---

## Overview

This records the mothership-gitops side of the `anthropic-oauth-proxy` ArgoCD
handoff after the Tailscale Operator migration. The source-level GitOps handoff
is implemented: mothership-gitops owns the ArgoCD Application, and
`tailnet-microservices/k8s` owns the rendered Kubernetes workload resources.

---

## Precondition

**Spec A must be deployed and verified before live adoption is considered complete.**

Verification checklist (performed by operator):
- [ ] Single-container pod running in `anthropic-oauth-proxy` namespace
- [ ] `anthropic-oauth-proxy` is reachable on the tailnet via Tailscale Operator
- [ ] Aperture routes to it without reconfiguration
- [ ] Claude Max OAuth tokens work end-to-end

These are live-cluster checks. They are not proven by this repository alone.

---

## Requirements

### R10: ArgoCD Application

ArgoCD Application in mothership-gitops:

- **Source:** `tailnet-microservices` repo, `k8s/` directory, Kustomize
- **Destination:** `anthropic-oauth-proxy` namespace on talos-prod-01
- **Sync wave:** Wave 8 (new slot between Homarr at 7 and ArgoCD HA at 99). The proxy doesn't depend on storage (wave 5/Longhorn) or other infrastructure services — a dedicated slot keeps it cleanly separated.
- **Sync policy:** Automated with prune and self-heal
- **No ExternalSecrets required** (zero secrets)

**File convention:** mothership-gitops uses a single file,
`apps/anthropic-oauth-proxy.yaml`, rather than the directory-per-app pattern
(`apps/<name>/application.yaml`). That is because this repo only owns the ArgoCD
Application handoff. The rendered workload resources, including the namespace,
service account, services, PVC, deployment, config map, and Tailscale Ingress,
live in `tailnet-microservices/k8s`.

The root app documents this as wave 8 in `apps/root.yaml`.

### R11: Zero-downtime migration ordering

This spec is sequenced AFTER Spec A specifically to ensure zero downtime:

1. Spec A ships the refactored manifests and deploys them (manually or via existing process)
2. Operator verifies proxy is reachable at `anthropic-oauth-proxy` on the tailnet (precondition above)
3. This spec adds ArgoCD management — ArgoCD adopts the already-running deployment
4. ArgoCD's automated sync with prune and self-heal takes over lifecycle management going forward

Because the deployment should already exist and be healthy when ArgoCD adopts it,
the intended migration path has no disruption. That zero-downtime claim still
requires live-cluster verification.

---

## Out of Scope

- Rust code changes (Spec A)
- Kubernetes manifest changes (Spec A)
- Aperture configuration
- Tailscale ACLs

---

## Success Criteria

- [x] ArgoCD Application YAML exists in mothership-gitops at `apps/anthropic-oauth-proxy.yaml`
- [x] Root app documents `anthropic-oauth-proxy` at wave 8 in `apps/root.yaml`
- [x] No ExternalSecrets are defined in the mothership-gitops Application
- [ ] ArgoCD sync status: Healthy, Synced
- [ ] Proxy remains reachable throughout live adoption (zero downtime)

---

## References

- `apps/root.yaml` — App of Apps sync wave ordering
- `apps/anthropic-oauth-proxy.yaml` — ArgoCD Application handoff
- tailnet-microservices `k8s/` — rendered workload resources
- tailnet-microservices operator migration docs — Spec A context and source-side manifests
