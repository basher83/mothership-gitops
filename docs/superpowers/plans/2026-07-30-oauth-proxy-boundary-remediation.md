# OAuth Proxy Authorization Boundary Remediation Plan

> **For the implementing operator:** Execute each task in its named owning
> repository. This plan does not authorize live-policy mutation or ArgoCD sync;
> those steps require the normal operator approval.

**Goal:** Make Tailscale membership the effective authorization boundary for
the credential-backed main proxy and Kubernetes API/RBAC port-forward access
the effective authorization boundary for the admin listener.

**Architecture:** Remove the cluster-routable admin path and isolate the
main-proxy ClusterIP with a least-privilege NetworkPolicy. Preserve the
existing broad population of tailnet clients. Promote the source-owned
manifests through this repository's manual ArgoCD gate, and prove the result
from both authorized and unauthorized trust zones.

**Technology:** Kustomize, Kubernetes Services and NetworkPolicy, Tailscale
Kubernetes Operator, Cilium, ArgoCD, `kubectl`, `tscli`, pre-commit

---

## Global Constraints

- Do not rerun the Codex Security scan as part of this plan.
- Do not edit source-owned Kubernetes manifests in `mothership-gitops`.
- Do not use imperative cluster patches. The deployed state must converge from
  Git.
- Do not modify the global Tailscale wildcard authorization in the same
  promotion. This plan preserves the tailnet-client contract.
- Use synthetic requests and non-secret test data. Do not print or capture
  OAuth tokens.
- Stop and hand work to `Omni-Scale` if success requires a Cilium, Talos, node,
  taint, or machine-class change.
- Keep the `anthropic-oauth-proxy` ArgoCD Application manually synchronized.

### Task 1: Record a Source-Repo Remediation Issue

**Owner:** `tailnet-microservices`

**Reference files:**

- Inspect: `/Users/basher8383/3I/forge/tailnet-microservices/k8s/kustomization.yaml`
- Inspect: `/Users/basher8383/3I/forge/tailnet-microservices/k8s/deployment.yaml`
- Inspect: `/Users/basher8383/3I/forge/tailnet-microservices/k8s/service.yaml`
- Inspect: `/Users/basher8383/3I/forge/tailnet-microservices/k8s/admin-service.yaml`
- Inspect: `/Users/basher8383/3I/forge/tailnet-microservices/k8s/ingress.yaml`
- Inspect: `/Users/basher8383/3I/forge/tailnet-microservices/k8s/config.toml`
- Reference: `/Users/basher8383/3I/lab/mothership-gitops/specs/oauth-proxy-boundary-remediation.md`

- [ ] Create one source-repo work item covering the two root controls, linked
  to `csf_f99c254cd45d3dc638c0d417`,
  `csf_002be178c7a4da1b19e2b7cc`,
  `csf_5add750c5303459820d27e00`, and
  `csf_f998388e28832b3deff1aeb2`.
- [ ] State explicitly that the two PKCE disruption findings are downstream
  effects, not independent projects.
- [ ] Copy the authorization decision, invariants, ownership boundary, and
  residual unknowns from the spec without claiming the controls already
  exist.
- [ ] Keep resource, telemetry, provider-semantics, disclosure, and local
  automation findings outside this issue.

### Task 2: Prove the Identities Needed by NetworkPolicy

**Owner:** `tailnet-microservices`, with read-only cluster observation by the
`mothership-gitops` operator

- [ ] Render the current source manifests and record the workload selector,
  Service ports, admin Service, Ingress backend, and probe definitions.

```bash
cd /Users/basher8383/3I/forge/tailnet-microservices
kubectl kustomize k8s > /tmp/anthropic-oauth-proxy-current.yaml
rg -n 'kind: (Service|Ingress|Deployment)|selector:|port:|targetPort:|probe' \
  /tmp/anthropic-oauth-proxy-current.yaml
```

- [ ] Read the live Ingress, its operator-created proxy resources, namespaces,
  labels, and owner references. Record only non-secret metadata in the source
  work item.

```bash
kubectl get ingress,service,deployment,pod -A \
  -l tailscale.com/parent-resource \
  -o custom-columns='KIND:.kind,NS:.metadata.namespace,NAME:.metadata.name,LABELS:.metadata.labels'
kubectl -n anthropic-oauth-proxy get ingress,service,deployment,pod \
  -o wide --show-labels
```

- [ ] If the label query returns nothing, follow the Ingress status and owner
  references to identify the operator-created proxy. Do not guess a selector.
- [ ] Establish whether Cilium enforces a standard Kubernetes NetworkPolicy
  across the observed namespace path. If this requires changing Cilium
  configuration, stop and hand the substrate work to `Omni-Scale`.
- [ ] Establish every health or readiness source that must reach port 8080.
  Do not add a broad node or namespace exception without a failing bounded
  reproduction.

### Task 3: Implement the Source-Owned Admin Boundary

**Owner:** `tailnet-microservices`

**Expected files:**

- Modify: `/Users/basher8383/3I/forge/tailnet-microservices/k8s/kustomization.yaml`
- Modify: `/Users/basher8383/3I/forge/tailnet-microservices/k8s/config.toml`
- Delete: `/Users/basher8383/3I/forge/tailnet-microservices/k8s/admin-service.yaml`
- Modify or add source-repo manifest assertion tests

- [ ] First add a failing deterministic test asserting that rendered manifests
  contain no Service selecting the admin port and no Tailscale route to port
  9090.
- [ ] Add a bounded local or disposable-cluster test proving that
  `kubectl port-forward deployment/anthropic-oauth-proxy 9090:9090` reaches a
  listener bound to pod loopback.
- [ ] Remove `admin-service.yaml` from Kustomize and delete the manifest.
- [ ] Bind the admin listener to loopback only after the port-forward test is
  proven.
- [ ] Assert that the rendered Service and Ingress inventory exposes only the
  main application path.
- [ ] If loopback port-forwarding fails, stop for design review. Do not restore
  a cluster-routable admin Service as the fallback.

### Task 4: Implement the Source-Owned Main-Proxy Boundary

**Owner:** `tailnet-microservices`

**Expected files:**

- Create: `/Users/basher8383/3I/forge/tailnet-microservices/k8s/networkpolicy.yaml`
- Modify: `/Users/basher8383/3I/forge/tailnet-microservices/k8s/kustomization.yaml`
- Modify or add source-repo manifest assertion tests

- [ ] First add a failing render test requiring an ingress policy that selects
  the proxy workload and restricts TCP port 8080.
- [ ] Write the policy from Task 2's observed stable namespace and pod labels.
  Permit the operator-managed Tailscale ingress proxy and only proven-required
  probe paths.
- [ ] Do not use the Tailscale device tag as a Kubernetes selector.
- [ ] Add a deterministic negative assertion rejecting unrestricted
  `podSelector: {}` or `namespaceSelector: {}` peers on port 8080.
- [ ] Render and inspect the complete Kustomize output.

```bash
cd /Users/basher8383/3I/forge/tailnet-microservices
kubectl kustomize k8s > /tmp/anthropic-oauth-proxy-proposed.yaml
kubectl apply --dry-run=server -f /tmp/anthropic-oauth-proxy-proposed.yaml
```

- [ ] Run the source repository's complete required test and pre-commit suite.
- [ ] Commit the admin and main-proxy boundary controls together because
  partial promotion would leave one of the two unauthorized paths open.

### Task 5: Perform the Cross-Repository Promotion Review

**Owner:** `mothership-gitops`

**Files:**

- Inspect: `/Users/basher8383/3I/lab/mothership-gitops/apps/anthropic-oauth-proxy.yaml`
- Update with evidence only:
  `/Users/basher8383/3I/lab/mothership-gitops/specs/oauth-proxy-boundary-remediation.md`

- [ ] Confirm the source commit changes only the intended admin topology,
  NetworkPolicy, tests, and directly related documentation.
- [ ] Confirm the ArgoCD Application still has no automated sync policy.
- [ ] Confirm the rendered namespace, resource names, selectors, and ports
  match the evidence used to construct the NetworkPolicy.
- [ ] Confirm the source CI and manifest assertions pass.
- [ ] Record the exact source commit selected for promotion.
- [ ] Capture a pre-change receipt without secrets:

```bash
kubectl -n argocd get application anthropic-oauth-proxy -o wide
kubectl -n anthropic-oauth-proxy get service,ingress,deployment,pod -o wide
tscli get device --name anthropic-oauth-proxy -n tailfb3ea.ts.net
tscli get policy -n tailfb3ea.ts.net --json | shasum -a 256
```

- [ ] Run this repository's documentation checks before committing an updated
  evidence record:

```bash
cd /Users/basher8383/3I/lab/mothership-gitops
pre-commit run --files \
  specs/oauth-proxy-boundary-remediation.md \
  docs/superpowers/plans/2026-07-30-oauth-proxy-boundary-remediation.md \
  docs/architecture.md
```

### Task 6: Manually Promote and Validate the Two Trust Boundaries

**Owner:** `mothership-gitops` operator

- [ ] Obtain explicit operator approval for the manual ArgoCD sync.
- [ ] Sync only the `anthropic-oauth-proxy` Application and wait for the
  Deployment to become healthy.
- [ ] From an authorized tailnet client, verify the existing hostname reaches
  `/health` and run one synthetic credential-backed inference request without
  logging request headers or tokens.
- [ ] From a disposable ordinary pod that does not match the allow policy,
  prove that connection attempts to the main Service fail.
- [ ] From the same ordinary pod, prove that no admin Service exists and that
  the pod cannot connect to port 9090 on the workload.
- [ ] With an operator identity authorized by Kubernetes RBAC, prove that a
  direct Deployment port-forward reaches a read-only admin endpoint.
- [ ] Verify that no Ingress or Tailscale resource routes port 9090.
- [ ] Inspect NetworkPolicy status and Cilium observations for unexpected
  denies. Do not weaken the policy without recording the exact failed path.
- [ ] Record commands, timestamps, source revision, ArgoCD revision, and
  redacted outcomes in the spec's evidence classification. Keep credentials
  and request headers out of the record.

### Task 7: Revalidate Findings and Close the Program

**Owner:** Codex Security finding owner

- [ ] Provide the source diff, rendered manifests, and live positive/negative
  receipts to the security owner.
- [ ] Revalidate the four high findings and the two downstream PKCE findings
  against the deployed revision.
- [ ] Do not mark findings resolved solely because ArgoCD reports
  `Healthy/Synced`.
- [ ] Change the spec status from `Planned` only after both source and live
  validation are complete.
- [ ] Add any discovered operational caveat to the matching durable document
  in `tailnet-microservices` or `docs/tailscale-networking.md`.

## Rollback

If the authorized tailnet path or required probes fail, revert the source
commit and promote that Git revision through the same manual ArgoCD gate. If
the admin port-forward fails, stop for topology review rather than recreating
the admin Service imperatively. Record that rollback reopens the authorization
finding. Any future Tailscale policy mutation must have a separate approval,
pre-change policy snapshot, validation, read-back, and rollback procedure.

## Deferred Follow-Up

After this boundary program is proven, create a separate proposal for making
the live Tailscale policy Git-managed, assigning the proxy a dedicated tag, and
decomposing the global wildcard grant. That proposal must inventory every flow
that currently relies on the wildcard before changing it. It must preserve the
decision that all intended tailnet clients may invoke the proxy unless the
operator explicitly changes that authorization contract.
