---
paths: specs/**/*.yaml, specs/**/*.yml
---

# Spec Analysis Rules

When working with spec files, follow this systematic approach:

## Analysis Framework

1. **Parse structure** — Understand the desired state definition
2. **Identify dependencies** — What blocks what? Map the dependency graph.
3. **Check current state** — What files/configs already exist in the repo?
4. **Gap analysis** — Desired state minus current state = work remaining
5. **Prioritize** — Blockers first, then dependencies, then independent work

## Spec Schema (omni.yaml pattern)

Specs define:

- Target infrastructure (clusters, nodes, networking)
- Locked decisions (non-negotiable constraints)
- Dependencies between components
- Current status per component (if tracked in spec)

## Output Format for Plans

Plans should include:

1. **Problem Statement** — Why does this work exist? What's the core challenge?
2. **Solution Summary** — High-level approach (1-2 sentences)
3. **Locked Decisions Table** — Non-negotiable constraints from spec
4. **Phases Table** — Ordered work breakdown:
   - Phase number and name
   - Status: `Not started` | `In progress` | `Blocked by X` | `Complete`
   - Notes: Key details or blockers
5. **Next Action** — Single, concrete step to advance the project

## Dependency Analysis

When identifying blockers:

- Network adjacency requirements (L2 access, routing)
- Bootstrap chicken-and-egg problems (auth, discovery, registration)
- Resource dependencies (what must exist before X can be created)
- Credential/secret dependencies (what auth is needed)

## Status Determination

To determine component status, check:

- Does implementation exist? (`terraform/`, `ansible/`, config files)
- Is there state? (`.tfstate`, deployed resources)
- Can you verify it's running? (API calls, health checks)
- Does it match spec? (drift detection)
