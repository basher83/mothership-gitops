# Spec: Operator Migration — GitOps (Spec B)

**Status:** Draft
**Created:** 2026-02-07
**Author:** Brent + Claude
**Scope:** mothership-gitops repo only

---

## Overview

Add ArgoCD management for the anthropic-oauth-proxy deployment after the Tailscale Operator migration (Spec A) is deployed and verified.

---

## Precondition

**Spec A must be deployed and verified before this spec is executed.**

Verification checklist (performed by operator):
- [ ] Single-container pod running in `anthropic-oauth-proxy` namespace
- [ ] `anthropic-oauth-proxy` is reachable on the tailnet via Tailscale Operator
- [ ] Aperture routes to it without reconfiguration
- [ ] Claude Max OAuth tokens work end-to-end

Do not proceed until all four are confirmed.

---

## Requirements

### R10: ArgoCD Application

Create an ArgoCD Application in mothership-gitops:

- **Source:** `tailnet-microservices` repo, `k8s/` directory, Kustomize
- **Destination:** `anthropic-oauth-proxy` namespace on talos-prod-01
- **Sync wave:** Wave 8 (new slot between Homarr at 7 and ArgoCD HA at 99). The proxy doesn't depend on storage (wave 5/Longhorn) or other infrastructure services — a dedicated slot keeps it cleanly separated.
- **Sync policy:** Automated with prune and self-heal
- **No ExternalSecrets required** (zero secrets)

**File convention:** Use a single file `apps/anthropic-oauth-proxy.yaml` rather than the directory-per-app pattern (`apps/<name>/application.yaml`). The proxy has no ExternalSecrets, no Ingress resources, and no supporting manifests — a single Application YAML is the entire definition. A directory would contain exactly one file.

Add to `apps/root.yaml` at wave 8.

### R11: Zero-downtime migration ordering

This spec is sequenced AFTER Spec A specifically to ensure zero downtime:

1. Spec A ships the refactored manifests and deploys them (manually or via existing process)
2. Operator verifies proxy is reachable at `anthropic-oauth-proxy` on the tailnet (precondition above)
3. This spec adds ArgoCD management — ArgoCD adopts the already-running deployment
4. ArgoCD's automated sync with prune and self-heal takes over lifecycle management going forward

Because the deployment already exists and is healthy when ArgoCD adopts it, there is no disruption. ArgoCD's first sync is effectively a no-op (manifests match what's running).

---

## Out of Scope

- Rust code changes (Spec A)
- Kubernetes manifest changes (Spec A)
- Aperture configuration
- Tailscale ACLs

---

## Success Criteria

- [ ] ArgoCD Application YAML exists in mothership-gitops at `apps/anthropic-oauth-proxy.yaml`
- [ ] Added to `apps/root.yaml` at wave 8
- [ ] ArgoCD sync status: Healthy, Synced
- [ ] No ExternalSecrets in the Application
- [ ] Proxy remains reachable throughout (zero downtime)

---

## References

- `apps/root.yaml` — App of Apps sync wave ordering
- Tailscale Operator docs — `tailscale.com/expose` annotation for headless Service exposure
- tailnet-microservices `specs/operator-migration-refactor.md` — Spec A (precondition)
