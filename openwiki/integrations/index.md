# Files

- [Radar UI, MCP, and read-only ArgoCD diffs](radar.md) - Radar's tailnet-only UI and MCP access, independent Kubernetes and ArgoCD authorization boundaries, persistent timeline, and validation contract. Explains deliberately missing telemetry integrations and the separate promotion paths for account policy and Secret-backed configuration.
- [Infisical and External Secrets ownership](secrets.md) - How scoped Infisical stores deliver credentials through External Secrets Operator to chart consumers, and how ArgoCD preserves operator ownership and stable encryption keys.
- [Tailnet ingress, egress, DNS, and access boundaries](tailscale-networking.md) - How Tailscale exposes cluster UIs and connects workloads to tailnet hosts, including operator-owned Service mutations, persistent CoreDNS forwarding, and Radar's ClusterIP bypass controls.
