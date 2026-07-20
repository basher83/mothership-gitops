# AGENTS.md

GitOps manifests for the `talos-prod-01` Kubernetes cluster. ArgoCD App of
Apps with sync waves. This file governs how agents work in this repo; the
knowledge itself lives in `docs/`.

---

## 1. Repo Boundary

* This repo owns what ArgoCD reconciles onto the cluster: applications,
  ingress, secrets wiring, storage, monitoring.
* The Talos/Omni substrate (cluster templates, machine classes, SideroLink,
  Cilium MTU rationale) is owned by `../Omni-Scale`. Do not duplicate or
  modify substrate knowledge here — reference it.
* If a fix requires substrate changes (node capacity, taints, machine
  classes), stop and say so. Do not work around substrate limits with
  manifest hacks.

---

## 2. Source of Truth

* `README.md` — bootstrap commands and recovery. Do not restate them elsewhere.
* `docs/architecture.md` — sync waves and sync policy exceptions.
* `docs/adding-applications.md` — new application checklist and patterns.
* `docs/tailscale-networking.md` — ingress and egress-to-tailnet patterns.
* `docs/backup-storage.md` — Longhorn backup tiers and MinIO wiring.
* `docs/troubleshooting.md` — symptom-shaped failures and fixes.
* New durable knowledge goes in the matching doc, not in this file. This
  file holds directives only.

---

## 3. Hard Requirements

* Any application with a web UI MUST be exposed via Tailscale Ingress. No
  cluster-internal-only UIs. No public exposure. Pattern in
  `docs/adding-applications.md`.
* Every new application MUST follow the checklist in
  `docs/adding-applications.md` — including sync-wave annotation, the
  `root.yaml` wave comment header, and ESO `ignoreDifferences` when
  ExternalSecrets are used.
* Secrets MUST flow Infisical → ESO → Secret. Never commit secret values.
  The only manual secret is the ESO bootstrap credential (see `README.md`).
* Verify Helm value keys against the chart's actual `values.yaml` before
  setting them. Known traps are recorded in `docs/troubleshooting.md`.

---

## 4. Sync Policy Discipline

* Default is automated sync with prune and self-heal. Deviations are
  deliberate and documented in `docs/architecture.md`.
* Do NOT enable prune on `longhorn`, `longhorn-helm`, or `coredns-tailscale`.
* Do NOT add automated sync to `argocd-ha` or `argocd-ha-helm` — the manual
  gate is the safety mechanism.
* Adding a new sync policy deviation requires a documented reason in
  `docs/architecture.md` in the same change.

---

## 5. Change Discipline

* The cluster state is Git. Prefer manifest changes over `kubectl` mutations.
  Imperative fixes are acceptable only for documented break-glass procedures
  (e.g. the SSA strategy patch in `docs/troubleshooting.md`) and must leave
  Git convergent afterward.
* One concern per commit. Conventional commit style, scoped to the app
  (`fix(phoenix): ...`, `feat(longhorn): ...`, `docs: ...`).
* Run `pre-commit run --files <changed>` before committing.
* When a change embeds operational knowledge (a gotcha, a caveat, a non-obvious
  value key), update the matching doc in the same commit.

---

## 6. Enforcement

* These are hard constraints, not suggestions.
* If a directive here contradicts a doc, this file wins; fix the doc.
* Work that violates this file is incomplete.

---

## Related

* [Omni-Scale](https://github.com/basher83/Omni-Scale) — substrate provisioning
* Infisical project `mothership-s0-ew` — secrets management
