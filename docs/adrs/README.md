# Architecture Decision Records

Architecture Decision Records capture consequential choices owned by
`mothership-gitops`: why the choice was made, what alternatives were rejected,
and which checked-in or externally managed controls carry the decision.

ADRs are historical records. Once accepted, their decision and rationale are
not rewritten to make later events look inevitable. A later decision that
changes an earlier one receives the next number and links back to the record it
supersedes. Minor corrections and links to current evidence may be added
without changing the historical decision.

## Statuses

- **Proposed:** under review and not yet authoritative.
- **Accepted:** the current architecture decision.
- **Superseded:** retained for history but replaced by a named later ADR.
- **Rejected:** considered and deliberately not adopted.

## Index

| ADR | Date | Status | Decision |
|---|---|---|---|
| [ADR-001](ADR-001-tailscale-api-server-proxy-deferral.md) | 2026-01-30 | Superseded by ADR-002 | Defer the Tailscale API server proxy in favor of Omni-only kubectl access |
| [ADR-002](ADR-002-enable-tailscale-api-server-proxy.md) | 2026-04-04 | Accepted | Enable the Tailscale API server proxy as a standing secondary kubectl path |

## Adding a Record

Use the next unused three-digit number and a descriptive lowercase filename:
`ADR-NNN-short-decision-title.md`. A record should state its status, date,
context, decision, consequences, alternatives, operational ownership, and
evidence. If it replaces another ADR, both records must link the supersession
chain.
