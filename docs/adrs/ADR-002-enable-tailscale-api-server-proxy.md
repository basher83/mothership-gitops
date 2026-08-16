# ADR-002: Enable the Tailscale API Server Proxy

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-04 |
| Authors | Brent, Astrogator |
| Supersedes | [ADR-001](ADR-001-tailscale-api-server-proxy-deferral.md) |

## Context

[ADR-001](ADR-001-tailscale-api-server-proxy-deferral.md) deferred a second
Kubernetes API access path because the Omni proxy was working and the added
complexity had no demonstrated benefit.

On 2026-04-03, an Omni certificate-expiry incident blocked `kubectl` access to
`talos-prod-01` for approximately two days. This fired ADR-001's explicit
revisit trigger and invalidated the assumption that a single Omni-dependent
path was operationally sufficient.

## Decision

Enable the Tailscale Kubernetes Operator's API server proxy in authenticated
mode as a standing secondary `kubectl` path.

Omni remains the primary Kubernetes access path and the authoritative
management plane for cluster lifecycle, machine provisioning, configuration
sync, and cluster creation or deletion. The Tailscale proxy provides
independent Kubernetes API access only; it does not replace those Omni
capabilities.

The resulting access model is:

| Role | Path | Purpose |
|---|---|---|
| Primary | Omni proxy via `omnictl kubeconfig` | Normal Kubernetes administration and Omni-integrated operations |
| Secondary | Tailscale API server proxy via `tailscale configure kubeconfig` | Independent Kubernetes API access when Omni's proxy is unavailable |

## GitOps Configuration

The accepted mode is checked into
[`apps/tailscale-operator/application.yaml`](../../apps/tailscale-operator/application.yaml):

```yaml
apiServerProxyConfig:
  mode: "true"
```

The operator hostname is `talos-prod-operator`, producing the secondary
kubeconfig context `talos-prod-operator.tailfb3ea.ts.net`.

Commit `76805e5ecbd47df1d68160e19bdaba3f557f862b` introduced the Helm value and
records the certificate incident as the adoption trigger.

## Authorization and External Policy

Authenticated proxy mode delegates Kubernetes identity through the Tailscale
Kubernetes application capability. The adopted live tailnet grant permits
tailnet members to reach `tag:k8s-operator` and impersonate
`system:masters`. Kubernetes' built-in cluster-admin binding supplies the
corresponding authorization in this single-administrator homelab.

The tailnet policy is externally managed and is not currently checked into
this repository. Consequently, the Helm value is source-verified here, while
the grant and tag ownership can drift and require live verification before
recovery procedures rely on them. A read-only check on 2026-07-30 confirmed
the `autogroup:member` grant, `tag:k8s-operator` destination,
`system:masters` impersonation group, and the matching live Kubernetes
ClusterRoleBinding. Moving that policy into version control is a separate
architecture decision and must not be inferred from this ADR.

## Consequences

The cluster now has an Omni-independent `kubectl` recovery path, reducing the
availability impact of an Omni proxy or certificate failure. The additional
path introduces another authentication, policy, and troubleshooting surface,
but the demonstrated outage justifies that continuing cost.

The `system:masters` impersonation grant is intentionally broad. It reflects
the single-administrator homelab context and must be revisited before the
tailnet or operator-access population expands.

## Alternatives Considered

Continuing with Omni alone was rejected because the incident demonstrated an
unacceptable single-path failure. Replacing Omni with Tailscale was rejected
because the proxy supplies Kubernetes API access but not Omni's lifecycle and
machine-management functions. Enabling the Tailscale proxy only during an
incident was rejected because recovery would then depend on making and
validating policy, Helm, and RBAC changes while the primary access path was
already unavailable.

## Operational Boundaries

The secondary path must be tested without disabling or demoting Omni. A working
Tailscale kubeconfig proves Kubernetes API access only; it does not prove Omni
recovery, Talos administration, or application ingress.

The operator's API server proxy is distinct from application-level Tailscale
Ingress resources. Decisions about who may invoke a credential-backed
application proxy or an application's admin listener are documented
separately and do not inherit authorization from this cluster-administration
ADR.

## Deferred Capabilities

Kubernetes session recording, API request event recording, and an HA
ProxyGroup remain deferred. The single-administrator environment has no
identified compliance need for the recording features, and a single proxy
replica is sufficient for a secondary recovery path. A demonstrated audit or
availability requirement should trigger a new ADR rather than silently expand
this one.

## Evidence

- [`apps/tailscale-operator/application.yaml`](../../apps/tailscale-operator/application.yaml)
  — accepted Helm configuration
- Git commit `76805e5ecbd47df1d68160e19bdaba3f557f862b` — adoption change and incident
  rationale
- Live verification on 2026-07-30 — `talos-prod-operator` device and tag,
  tailnet Kubernetes capability grant, kubeconfig context, and
  `system:masters` ClusterRoleBinding
- [Tailscale API server proxy documentation](https://tailscale.com/docs/kubernetes-operator/api-server-access)
  — authoritative meaning of authenticated in-process mode and kubeconfig
  setup
- [Architecture](../architecture.md) — current platform architecture and sync
  policy
- [ADR index](README.md) — status and supersession chain
