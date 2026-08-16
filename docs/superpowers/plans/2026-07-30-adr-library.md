# Architecture Decision Record Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish `docs/adrs/` as the canonical home for this repository's
architecture decisions and import the Tailscale API server proxy decision as a
clear supersession chain.

**Architecture:** Preserve the original 2026-01-30 deferral as ADR-001 and
record the 2026-04-04 adoption as the active ADR-002. An index defines status
semantics and navigation, while `README.md` and `docs/architecture.md` point
readers to the canonical decision library.

**Tech Stack:** Markdown, Git history, GitOps YAML, pre-commit

## Global Constraints

- Leave
  `/Users/basher8383/3I/Vault/TheMothership/Resources/adrs/ADR-001-Tailscale-API-Server-Proxy-Deferral.md`
  unchanged as a historical source copy.
- Preserve the original authors, dates, decision rationale, alternatives, and
  revisit triggers.
- Treat checked-in GitOps state as authoritative for the adopted configuration.
- Describe the live tailnet ACL as an externally managed dependency, not as
  policy-as-code owned by this repository.
- Do not change manifests, live tailnet policy, cluster state, or ADR numbering
  outside this import.

---

### Task 1: Create the ADR Library and Decision Chain

**Files:**

- Create: `docs/adrs/README.md`
- Create: `docs/adrs/ADR-001-tailscale-api-server-proxy-deferral.md`
- Create: `docs/adrs/ADR-002-enable-tailscale-api-server-proxy.md`

**Interfaces:**

- Consumes: the Vault historical source, commit `76805e5`, and
  `apps/tailscale-operator/application.yaml`
- Produces: a canonical ADR index and an explicit ADR-001 → ADR-002
  supersession chain

- [x] Create `docs/adrs/README.md` defining ADR purpose, statuses, immutability
  expectations, numbering, and the two-entry decision index.
- [x] Write ADR-001 with status `Superseded by ADR-002`, retaining the
  2026-01-30 deferral, its rationale, consequences, alternatives, and triggers.
- [x] Write ADR-002 with status `Accepted`, recording the 2026-04-03 trigger,
  the 2026-04-04 adoption, the checked-in `apiServerProxyConfig.mode: "true"`
  configuration, dual-path operational boundary, ACL dependency, and deferred
  capabilities.
- [x] Make both records link to each other and distinguish the primary Omni
  management plane from the secondary Tailscale kubectl path.

### Task 2: Integrate and Verify the ADR Library

**Files:**

- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Verify:
  `/Users/basher8383/3I/Vault/TheMothership/Resources/adrs/ADR-001-Tailscale-API-Server-Proxy-Deferral.md`

**Interfaces:**

- Consumes: the ADR index produced by Task 1
- Produces: repository-level navigation and an architecture-level decision
  reference

- [x] Add the ADR library to the repository's Related links.
- [x] Add an Architecture Decisions section linking the index and active
  Tailscale API server proxy decision.
- [x] Add `docs/adrs/` to the repository structure and source-of-truth map.
- [x] Verify the adopted mode directly from
  `apps/tailscale-operator/application.yaml`.
- [x] Verify commit `76805e5` records the incident and adoption rationale.
- [x] Hash the Vault source before and after the work and confirm it is
  unchanged.
- [x] Run:

```bash
pre-commit run --files \
  AGENTS.md \
  README.md \
  docs/architecture.md \
  docs/adrs/README.md \
  docs/adrs/ADR-001-tailscale-api-server-proxy-deferral.md \
  docs/adrs/ADR-002-enable-tailscale-api-server-proxy.md \
  docs/superpowers/plans/2026-07-30-adr-library.md
git diff --check
```
