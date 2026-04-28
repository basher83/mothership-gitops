# Documentation Audit Report

Generated: 2026-04-28 | Baseline commit: 76805e5 | Updated after doc cleanup and cluster verification | Scope: working tree docs, manifests, live cluster, and tailnet-microservices cross-reference

## Executive Summary

This audit checked the user-facing documentation against the checked-in GitOps manifests. The target documents were `README.md`, `CLAUDE.md`, `docs/backup-storage.md`, and `specs/operator-migration-gitops.md`. The spec was included after cross-referencing `/Users/basher8383/3I/forge/tailnet-microservices/docs/audits/AUDIT_REPORT_2026-04-28.md`, which identified mothership-side drift for the `anthropic-oauth-proxy` ArgoCD handoff. This report itself is under `docs/audits/`, so it should be excluded from future audit scopes.

The source-level documentation drift found by the audit has been patched. `CLAUDE.md` now describes the two-stage bootstrap path, Phoenix wave 9, sync-policy exceptions, the managed CoreDNS patch, and the external-source nature of `anthropic-oauth-proxy`. `README.md` now includes Anthropic OAuth Proxy and Phoenix in the architecture and structure sections. `docs/backup-storage.md` now describes the MinIO policy scope accurately. `specs/operator-migration-gitops.md` is now a completed handoff record with live validation partially complete.

The manifests parse successfully as YAML using Ruby's `YAML.load_stream` across `apps/**/*.yaml` and `bootstrap/**/*.yaml`. Kubernetes MCP checks confirmed the high-value live-cluster items: `anthropic-oauth-proxy` is Healthy/Synced in ArgoCD, the workload is running, Tailscale Ingress is active, CoreDNS forwards to the live Tailscale nameserver IP, and Longhorn backup-tier labels match the documented PVC mapping. The remaining work is client-path validation for Aperture and Claude Max OAuth, plus optional pod-level SNI testing.

| Metric | Count |
|--------|-------|
| Documents scanned | 4 |
| Claims checked | 84 |
| Verified true or corrected | 73 |
| Open false claims | 0 |
| Resolved false claims | 12 |
| Needs live-client/path review | 2 |

## Resolved Findings

### README.md

| Original Line | Claim | Resolution |
|------|-------|------------|
| 7 | "Single bootstrap command deploys" the platform through App of Apps. | Updated to say bootstrap installs prerequisites first, then ArgoCD reconciles. |
| 9-15 | Architecture list omitted Anthropic OAuth Proxy and Phoenix. | Added Anthropic OAuth Proxy at item 7 and Phoenix at item 8. |
| 109-121 | Structure block omitted `apps/anthropic-oauth-proxy.yaml` and `apps/phoenix/`. | Added both entries to the structure block. |

### CLAUDE.md

| Original Line | Claim | Resolution |
|------|-------|------------|
| 42 | "Single bootstrap command deploys the entire platform through ordered sync waves." | Rewritten as a two-stage bootstrap process with Helm prerequisites followed by ArgoCD reconciliation. |
| 45 | "Wave 1: ArgoCD (non-HA bootstrap)." | Reframed as prerequisite installation instead of an app-of-apps sync wave. |
| 51-52 | The wave list omitted Phoenix. | Added Phoenix at wave 9. |
| 55 | Automated prune/self-heal summary ignored exceptions. | Rewritten to list ArgoCD HA, nested `argocd-ha-helm`, Longhorn root prune, and `coredns-tailscale` prune exceptions. |
| 146 | CoreDNS patch note implied only manual reapplication. | Rewritten to describe the managed `coredns-tailscale` Application and the remaining ClusterIP revalidation concern. |
| 198-205 | Bootstrap block described old single-apply flow and only one HA sync. | Rewritten to point to README as command source of truth and include both HA patch commands. |

### docs/backup-storage.md

| Original Line | Claim | Resolution |
|------|-------|------------|
| 23 | IAM policy is "Scoped to `longhorn-backups` bucket only." | Rewritten to say bucket and object operations are scoped to `longhorn-backups`, while global bucket listing is allowed for S3 client compatibility. |

### specs/operator-migration-gitops.md

| Original Line | Claim | Resolution |
|------|-------|------------|
| 3 | Status is `Draft`. | Converted to `Implemented handoff record; live validation partially complete`. |
| 42 | The proxy has "no Ingress resources, and no supporting manifests" in the consumed source repo. | Rewritten to clarify that mothership-gitops owns only the ArgoCD Application, while `tailnet-microservices/k8s` owns rendered workload resources. |
| 70-71 | Application YAML and root wave placement success criteria were unchecked. | Checked source-level criteria for the Application, root wave documentation, no ExternalSecrets, ArgoCD Healthy/Synced, and Tailscale Ingress; left client-path validation criteria unchecked. |

## Verified Claims

The main web UI exposure requirement is backed by manifests. ArgoCD, Longhorn, Netdata, Homarr, and Phoenix all have local `Ingress` resources with `ingressClassName: tailscale`; see `apps/argocd-ingress/ingress.yaml:1-16`, `apps/longhorn/ingress.yaml:1-16`, `apps/netdata/ingress.yaml:1-18`, `apps/homarr/ingress.yaml:1-18`, and `apps/phoenix/ingress.yaml:1-37`. The Anthropic OAuth Proxy is external-source managed, but its consumed `tailnet-microservices/k8s/ingress.yaml` also uses `ingressClassName: tailscale`, and `kubectl kustomize k8s` renders that Ingress from the source repo.

The Infisical ClusterSecretStore mapping in `CLAUDE.md` is accurate. The four stores exist and point at `/tailscale-operator`, `/netdata`, `/homarr`, and `/longhorn`; see `apps/external-secrets/clustersecretstore.yaml:11-32`, `apps/external-secrets/clustersecretstore.yaml:36-57`, `apps/external-secrets/clustersecretstore.yaml:61-82`, and `apps/external-secrets/clustersecretstore.yaml:86-107`.

The ExternalSecret guidance about using `sync-wave: "0"` is consistent with current app directories. Tailscale, Netdata, Homarr, and Longhorn ExternalSecrets all use wave 0; see `apps/tailscale-operator/externalsecret.yaml:7-15`, `apps/netdata/externalsecret.yaml:7-15`, `apps/homarr/externalsecret.yaml:7-15`, and `apps/longhorn/externalsecret.yaml:6-15`.

The Helm value gotchas in `CLAUDE.md` match the checked-in values. Homarr uses `persistence.homarrDatabase.storageClassName: longhorn`; see `apps/homarr/application.yaml:20-25`. ArgoCD Redis HA uses `redis-ha.persistentVolume.storageClass: longhorn`; see `apps/argocd/ha-upgrade.yaml:36-41`.

The backup tier schedule table is consistent with the Longhorn RecurringJobs. Critical uses `0 */4 * * *` with retain 42, important uses `0 2 * * *` with retain 14, and standard uses `0 3 * * 0` with retain 4; see `apps/longhorn/recurringjobs.yaml:12-23`, `apps/longhorn/recurringjobs.yaml:28-39`, and `apps/longhorn/recurringjobs.yaml:44-55`.

The backup storage GitOps file list is complete for the checked-in Longhorn backup implementation. All five files referenced at `docs/backup-storage.md:83-87` exist and match the described roles.

The cross-repo ArgoCD handoff itself is confirmed. `apps/anthropic-oauth-proxy.yaml:1-31` defines an automated ArgoCD Application in wave 8, targets `https://github.com/basher83/tailnet-microservices.git`, uses `targetRevision: main`, consumes `path: k8s`, deploys to namespace `anthropic-oauth-proxy`, and enables prune/self-heal with `CreateNamespace=true` and `ServerSideApply=true`.

## Live Cluster Verification

Kubernetes MCP checks confirmed that the live `anthropic-oauth-proxy` ArgoCD Application is `Healthy` and `Synced`. Its last operation succeeded, it is sourced from `https://github.com/basher83/tailnet-microservices.git` at `path: k8s`, and it deploys to the `anthropic-oauth-proxy` namespace.

The live workload is running as a single ready pod, `anthropic-oauth-proxy-855fb454d8-hxcn8`, with `READY 1/1`, `STATUS Running`, and zero restarts at the time of verification. The deployment has one replica, one ready replica, one available replica, and uses `strategy.type: Recreate` with image `ghcr.io/basher83/tailnet-microservices/anthropic-oauth-proxy:sha-73688d8`.

The Tailscale Ingress is active. It uses `ingressClassName: tailscale`, routes `/` to service `anthropic-oauth-proxy` on port 80, and reports load balancer hostname `anthropic-oauth-proxy.tailfb3ea.ts.net` on port 443.

The Tailscale DNS path is consistent. `DNSConfig` `ts-dns` reports nameserver IP `10.108.67.5`, the `nameserver` Service in `tailscale-operator` has ClusterIP `10.108.67.5`, and the live CoreDNS ConfigMap forwards both `ts.net` and `tailfb3ea.ts.net` to `10.108.67.5`.

The documented backup PVC mapping is accurate in the live cluster. Homarr's `homarr-database` Longhorn volume is labeled `recurring-job-group.longhorn.io/critical: enabled`; the three ArgoCD Redis HA volumes are labeled `important`; and the three documented Netdata volumes are labeled `standard`. Those checked Longhorn volumes report healthy robustness and recent backups.

The proxy image does not include `wget` or `curl`, so an in-container HTTP `/health` response body was not collected. Kubernetes liveness/readiness probes are passing, which verifies the endpoint from kubelet's perspective but not its JSON payload.

## Pattern Summary

| Pattern | Count | Root Cause |
|---------|-------|------------|
| Stale bootstrap model | 4 | Resolved in README and CLAUDE.md. |
| Incomplete app inventory | 3 | Resolved in README and CLAUDE.md. |
| Over-broad sync policy summary | 1 | Resolved in CLAUDE.md. |
| Overstated IAM scoping | 1 | Resolved in docs/backup-storage.md. |
| Stale migration spec | 3 | Resolved in specs/operator-migration-gitops.md; live Kubernetes object validation is partially complete. |

## Human Review Queue

- `README.md:44-47` claims MTU 1450 avoids Tailscale Ingress degradation of roughly 22 KB/s versus 99 Mbps. This is an operational measurement from Omni/Cilium behavior, not something verifiable from this repository alone.
- `CLAUDE.md` documents a ServerSideApply deployment strategy failure mode and remediation. The Phoenix manifest contains the relevant `rollingUpdate: null` mitigation at `apps/phoenix/application.yaml:27-32`, but the historical failure mode itself requires cluster/API-server behavior to validate.
- `CLAUDE.md` says preserving the actual tailnet FQDN preserves SNI for valid TLS with Tailscale Serve. The egress services and DNS forwarding exist, but TLS/SNI validity should be verified from a pod that has a usable HTTP/TLS client.
- `specs/operator-migration-gitops.md` still leaves Aperture routing and Claude Max OAuth end-to-end checks open. Kubernetes object state is healthy, but those claims require client-path testing.
- The previous zero-downtime wording has been softened. The live deployment is single-replica with `strategy.type: Recreate`, so future rollouts can interrupt service briefly and should not be described as zero-downtime.

## Cross-Repo Reference

The cleanup audit in `/Users/basher8383/3I/forge/tailnet-microservices/docs/audits/AUDIT_REPORT_2026-04-28.md` includes a GitOps Deployment Cross-Check section. That report confirmed the mothership-side ArgoCD Application shape and flagged `specs/operator-migration-gitops.md` in this repo as stale. I verified that finding directly against this repo and the source repo before patching the spec.

The tailnet repo currently resolves locally to `642b7a3` with latest commit `docs: fix remaining operator doc drift`. The earlier cross-check finding has been resolved in this repo by converting `specs/operator-migration-gitops.md` into a completed handoff record.

## Verification Commands Run

```bash
git rev-parse --short HEAD
rg --files
nl -ba README.md
nl -ba CLAUDE.md
nl -ba docs/backup-storage.md
rg -n "apps/|bootstrap/|\\.yaml|kubectl|helm|argocd|sync-wave|Ingress|ExternalSecret|ClusterSecretStore|StorageClass|RecurringJob|AWS_|every|Daily|Weekly|hours|days|retention|prune|selfHeal|manual|automated" README.md CLAUDE.md docs/backup-storage.md
rg -n "ingressClassName: tailscale|kind: Ingress|kind: Application|kind: ExternalSecret|kind: ClusterSecretStore|kind: StorageClass|kind: RecurringJob|prune: false|prune: true|selfHeal: true|sync-wave" apps bootstrap
ruby -e 'require "yaml"; Dir["{apps,bootstrap}/**/*.y{a,}ml"].each { |f| YAML.load_stream(File.read(f)); puts "OK #{f}" }'
kubectl kustomize /Users/basher8383/3I/forge/tailnet-microservices/k8s
rg -n 'Single bootstrap command|CoreDNS patch on Talos is volatile|Scoped to `longhorn-backups` bucket only|no Ingress resources|Status is `Draft`' CLAUDE.md README.md docs/backup-storage.md specs/operator-migration-gitops.md || true
# Kubernetes MCP checks:
# - applications.argoproj.io/anthropic-oauth-proxy -n argocd
# - pods, services, ingress -n anthropic-oauth-proxy
# - deployment/anthropic-oauth-proxy -n anthropic-oauth-proxy
# - pvc -A
# - volumes.longhorn.io for documented backup PVCs
# - dnsconfigs.tailscale.com/ts-dns -n tailscale-operator
# - service/nameserver -n tailscale-operator
# - configmap/coredns -n kube-system
```
