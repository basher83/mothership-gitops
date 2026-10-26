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

Tiered StorageClasses select recurring-job groups for new volumes. Each
RecurringJob retains its short tier group (`critical`, `important`, `standard`)
for manually labeled volumes and also declares the matching `backup-<tier>`
group selected by the StorageClass. These are two group names on the same job,
not additional schedules.

The group aliases reconcile a source mismatch without changing immutable
StorageClass parameters or replacing StorageClasses. Job names, schedules,
retention counts and manual tier-label instructions are unchanged.

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

## Verification boundary for the group-alias correction

The source correction is not proof of backup coverage. After separately approved
publication and reconciliation, verify the deployed RecurringJob groups and the
actual group labels on each Longhorn volume. Existing labels and default-class
volumes are not changed by this patch; volumes without a matching label still
need an explicit coverage decision. The mapping above does not cover Phoenix or
the OAuth proxy credential volume.

Confirm recent successful backups at the target and exercise a representative
restore before claiming recoverability. Retention values are backup counts, not
guaranteed calendar coverage. Do not force-replace StorageClasses, recreate PVCs,
or relabel volumes merely to deploy this correction.

The Longhorn application self-heals from Git. Publishing this change can enable
scheduled backups for volumes already labeled `backup-<tier>`; publication is an
operational step, not just documentation. Review target capacity and coverage
first. Reverting the added aliases would remove that enrollment path again;
it would not restore data or undo backups already taken.

## GitOps Files

| File | Purpose |
|------|---------|
| `apps/longhorn/application.yaml` | Helm values (includes BackupTarget config) |
| `apps/longhorn/externalsecret.yaml` | MinIO credentials from Infisical |
| `apps/longhorn/minio-egress.yaml` | Tailscale egress Service |
| `apps/longhorn/recurringjobs.yaml` | Backup schedules (3 tiers) |
| `apps/longhorn/storageclasses.yaml` | Tiered StorageClasses |
