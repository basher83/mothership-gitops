# Documentation Audit Report

Generated: 2026-06-20 | Baseline commit: 902154d | Scope: working tree docs and GitOps manifests

## Executive Summary

This audit checked the current user-facing repo documentation against checked-in GitOps manifests. The primary drift was around External Secrets documentation: Phoenix added a fifth Infisical `ClusterSecretStore`, and the sync-wave docs still described a separate top-level wave 3 for stores even though the current implementation keeps the External Secrets stack in root wave 2 with child-app sub-waves.

The source-level drift found by this pass has been patched. Existing historical audit files were excluded from the audit scope, except for an already-applied note clarifying that the 2026-04-28 “four stores” statement was true only at that earlier baseline.

| Metric | Count |
|--------|-------|
| Documents scanned | 7 |
| Manifest inventories checked | 6 |
| Resolved source-level false claims | 4 |
| Open source-level false claims | 0 |
| Live-cluster claims not revalidated | 2 |

## Documents Scanned

- `README.md`
- `docs/adding-applications.md`
- `docs/architecture.md`
- `docs/backup-storage.md`
- `docs/tailscale-networking.md`
- `docs/troubleshooting.md`
- `specs/operator-migration-gitops.md`

Existing reports under `docs/audits/` were treated as historical records, not current source documentation.

## Resolved Findings

| File | Claim | Reality | Resolution |
|------|-------|---------|------------|
| `docs/adding-applications.md` | ClusterSecretStore table listed four Infisical stores. | `apps/external-secrets/clustersecretstore.yaml` now defines five stores, including `infisical-phoenix` for `/phoenix`. | Added `infisical-phoenix` to the table. |
| `docs/architecture.md` | Sync waves listed `Wave 3: ClusterSecretStores`. | The root app uses wave 2 for `external-secrets`; within that child app, `external-secrets-helm` is sub-wave 1 and ClusterSecretStores are sub-wave 2. | Rewrote the wave entry as root wave 2 with child sub-waves. |
| `apps/root.yaml` | Wave comment header listed `3: ClusterSecretStore`. | Same implementation reality as above: stores are child-app sub-wave 2 under the root wave 2 External Secrets stack. | Updated the load-bearing comment header. |
| `README.md` | Structure comment said `external-secrets/` was `wave 2-3`. | Current implementation is root wave 2 with child waves 1-2. | Updated the structure comment. |

## Verified Claims

The Infisical store inventory now matches source: five `ClusterSecretStore` resources point to `/tailscale-operator`, `/netdata`, `/homarr`, `/longhorn`, and `/phoenix` in `apps/external-secrets/clustersecretstore.yaml`.

All checked-in `ExternalSecret` resources use `argocd.argoproj.io/sync-wave: "0"` and reference the expected stores: Tailscale, Netdata, Homarr, Longhorn, and Phoenix.

All local checked-in `Ingress` resources use `ingressClassName: tailscale`. The audit verified six local Tailscale Ingress resources: ArgoCD, Longhorn, Netdata, Homarr, Phoenix, and Phoenix OTLP. The Anthropic OAuth Proxy remains external-source managed through `tailnet-microservices/k8s` and was not live-client revalidated in this pass.

Longhorn backup documentation matches the checked-in resources: three `RecurringJob` resources define critical, important, and standard schedules; three tiered StorageClasses map to those job groups; the MinIO policy scopes bucket and object access to `longhorn-backups` while allowing global bucket listing for S3 client compatibility.

The documented sync-policy exceptions match current manifests: `argocd-ha` and nested `argocd-ha-helm` are manual, `longhorn` has root-app `prune: false`, and `coredns-tailscale` has automated self-heal with `prune: false`.

## Human Review / Live Validation Queue

- `specs/operator-migration-gitops.md` still has two intentionally open client-path checks: Aperture routing and Claude Max OAuth end-to-end flow.
- `docs/backup-storage.md` lists current PVC-to-backup-tier labels as live operational state. This pass validated the GitOps backup machinery, not live Longhorn volume labels.

## Commands Run

```bash
ruby -e 'require "yaml"; Dir["{apps,bootstrap}/**/*.y{a,}ml"].each { |f| YAML.load_stream(File.read(f)); puts "OK #{f}" }'
```

```bash
ruby <<'RUBY'
# Inventory validation for ClusterSecretStores, ExternalSecrets, Ingresses,
# StorageClasses, RecurringJobs, and Applications.
RUBY
```

```bash
pre-commit run --files README.md apps/root.yaml docs/adding-applications.md docs/architecture.md docs/audits/AUDIT_REPORT_2026-04-28.md docs/audits/AUDIT_REPORT_2026-06-20.md
```
