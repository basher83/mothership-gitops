# Backup Storage

Longhorn volumes back up to MinIO S3 on TrueNAS Scale via Tailscale.

## Infrastructure

| Component | Location |
|-----------|----------|
| MinIO | TrueNAS Scale (`truenas-scale.tailfb3ea.ts.net:9000`) |
| Bucket | `longhorn-backups` |
| Connectivity | Tailscale egress Service |

## Credentials

Stored in Infisical under `/longhorn` path, synced via ExternalSecret:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_ENDPOINTS` (includes protocol and port)

## IAM Policy

Bucket and object operations are scoped to `longhorn-backups`. The policy also
allows global bucket listing for S3 client compatibility. See
`minio-config/longhorn-backups-policy.json`.

## Backup Tiers

| Tier | Cron | Retention | Use Case |
|------|------|-----------|----------|
| critical | `0 */4 * * *` | 42 (7 days) | Databases, stateful apps |
| important | `0 2 * * *` | 14 (14 days) | User data, configs |
| standard | `0 3 * * 0` | 4 (4 weeks) | Logs, replaceable data |

## Volume Tier Assignments

Current PVC→tier mapping (label these after cluster rebuild):

| Namespace | PVC | Tier |
|-----------|-----|------|
| homarr | homarr-database | critical |
| argocd | data-argocd-ha-helm-redis-ha-server-0 | important |
| argocd | data-argocd-ha-helm-redis-ha-server-1 | important |
| argocd | data-argocd-ha-helm-redis-ha-server-2 | important |
| netdata | netdata-parent-database | standard |
| netdata | netdata-parent-alarms | standard |
| netdata | netdata-k8s-state-varlib | standard |

### Labeling Existing Volumes

Longhorn volumes require labels directly (not PVCs). After cluster rebuild,
get volume names and apply labels per the mapping above:

```bash
# Get volume name from PVC
kubectl get pvc <pvc-name> -n <namespace> -o jsonpath='{.spec.volumeName}'

# Label volume for tier
kubectl label volumes.longhorn.io <volume-name> -n longhorn-system \
  recurring-job-group.longhorn.io/<tier>=enabled
```

## StorageClasses for New Volumes

Tiered StorageClasses auto-assign recurring jobs to new volumes:

| StorageClass | Backup Tier |
|--------------|-------------|
| `longhorn-critical` | Every 4 hours, 7-day retention |
| `longhorn-important` | Daily, 14-day retention |
| `longhorn-standard` | Weekly, 4-week retention |
| `longhorn` (default) | No automatic backups |

Use in PVC spec:

```yaml
spec:
  storageClassName: longhorn-critical
```

## Pre-Upgrade Snapshots

Take a manual Longhorn snapshot before any upgrade that migrates an app's
on-disk schema (for example, a Phoenix major on its single SQLite database).
Reverting the chart in Git does not undo a migration. Rollback means reverting
the bump and restoring the volume from the snapshot. This matters most for
volumes with no backup tier, such as `phoenix/phoenix-helm-data-pvc`, where
the snapshot is the only copy.

```bash
VOL=$(kubectl -n <ns> get pvc <pvc> -o jsonpath='{.spec.volumeName}')
cat <<EOF | kubectl apply -f -
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: <app>-pre-<version>-<yyyymmdd>
  namespace: longhorn-system
spec:
  volume: ${VOL}
  createSnapshot: true
EOF
kubectl -n longhorn-system get snapshots.longhorn.io <name> \
  -o jsonpath='{.status.readyToUse}'
```

A snapshot taken while the pod runs is crash-consistent, which is acceptable
for SQLite. These Snapshot objects are not managed by ArgoCD. Delete them once
the upgraded version has run cleanly under normal load, and record outstanding
ones below so they do not accumulate.

| Snapshot | Volume | Created | Delete after |
|----------|--------|---------|--------------|
| `phoenix-pre-v21-20261030` | phoenix-helm-data-pvc | 2026-10-30 | Phoenix 21 stable (target 2026-11-13) |

```bash
kubectl -n longhorn-system delete snapshots.longhorn.io <name>
```

## GitOps Files

| File | Purpose |
|------|---------|
| `apps/longhorn/application.yaml` | Helm values (includes BackupTarget config) |
| `apps/longhorn/externalsecret.yaml` | MinIO credentials from Infisical |
| `apps/longhorn/minio-egress.yaml` | Tailscale egress Service |
| `apps/longhorn/recurringjobs.yaml` | Backup schedules (3 tiers) |
| `apps/longhorn/storageclasses.yaml` | Tiered StorageClasses |
