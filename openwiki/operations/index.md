# Files

- [Bootstrap gates, recovery, and reconciliation triage](bootstrap-and-triage.md) - Follow the authoritative bootstrap and recovery procedure, then distinguish reconciliation drift, stale operation failures, runtime faults, and substrate capacity limits before requesting a sync.
- [Longhorn persistence, backup tiers, and restore safety](storage-and-backups.md) - How PVCs use Longhorn storage and scheduled MinIO backups over Tailscale, with safeguards for deletion, upgrades, snapshots, and cluster rebuilds. Explains backup tier wiring and the limits of declarative configuration as recovery evidence.
