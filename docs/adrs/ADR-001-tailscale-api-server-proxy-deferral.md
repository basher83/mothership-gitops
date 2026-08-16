# ADR-001: Defer the Tailscale API Server Proxy

| Field | Value |
|---|---|
| Status | Superseded by [ADR-002](ADR-002-enable-tailscale-api-server-proxy.md) on 2026-04-04 |
| Date | 2026-01-30 |
| Authors | Brent, Astrogator |
| Reviewers | Brent |

## Context

The homelab Kubernetes cluster runs on Talos Linux and is managed by Sidero
Omni. The Tailscale Kubernetes Operator was already deployed for networking,
including service exposure and tailnet connectivity. Tailscale could also
provide a Kubernetes API server proxy, giving tailnet identities a separate
`kubectl` access path.

During the initial cluster setup, Omni's existing Kubernetes proxy was the
working and actively used management path. The question was whether to enable
Tailscale's API server proxy alongside it.

## Decision

Defer the Tailscale API server proxy and use the Omni Kubernetes proxy as the
sole `kubectl` access path.

This was a deferral rather than a permanent rejection. The proxy would become
valuable if Omni-independent access, disaster-recovery testing, or a redundant
operational path became necessary.

## Decision Factors

Omni already provided working Kubernetes access, so adding a second path would
have duplicated capability without an immediate operational requirement. The
decision favored fewer moving parts, fewer ACL and RBAC rules, and one
management path to troubleshoot.

The Tailscale Operator therefore remained scoped to networking. No API server
proxy Helm values, tailnet Kubernetes capability grant, or additional RBAC
configuration was introduced by this decision.

## Consequences

The positive consequence was a simpler operator configuration and a single
source of truth for cluster access. The negative consequence was dependence on
Omni availability: if its proxy failed, ordinary `kubectl` administration
would be unavailable until an alternative path was configured. Talos control
plane access through `talosctl` remained a separate capability and did not
replace Kubernetes API access.

## Alternatives Considered

Enabling both proxies would have provided redundancy but required additional
Helm, tailnet-policy, and RBAC configuration. Replacing Omni's proxy with the
Tailscale proxy would have removed the Omni dependency for `kubectl`, but
Tailscale would not replace Omni's cluster lifecycle, machine-management, and
configuration capabilities.

## Revisit Triggers

The decision was to be revisited if an Omni outage affected cluster
management, Omni-independent disaster-recovery operations became necessary,
non-Omni clusters entered the environment, or an operating environment could
reach Tailscale but not Omni.

## Outcome

The first trigger fired during the Omni certificate-expiry incident on
2026-04-03, which blocked the primary `kubectl` path for approximately two
days. The resulting adoption decision is recorded in
[ADR-002](ADR-002-enable-tailscale-api-server-proxy.md).

## Historical Source

This record was migrated from
`TheMothership/Resources/adrs/ADR-001-Tailscale-API-Server-Proxy-Deferral.md`.
The Vault file remains an unchanged historical source copy. This repository is
the canonical home for the split ADR chain.
