# Adding Applications

Checklist and patterns for adding a new application to the cluster. For wave
ordering and sync policy context see `architecture.md`.

## Checklist (Directory Pattern)

For apps with supporting resources in this repo (ExternalSecrets, Ingress,
extra manifests):

1. Create `apps/<app-name>/` with `application.yaml` (Helm chart source +
   values).
2. If the app has a web UI, add `ingress.yaml` with a Tailscale Ingress
   (required — see below).
3. If the app needs secrets, follow [ExternalSecrets Integration](#externalsecrets-integration).
4. Add an Application manifest to `apps/root.yaml` with a sync-wave
   annotation, and update the wave comment header in `root.yaml`.
5. If using ExternalSecrets, add `ignoreDifferences` for ESO default fields
   (see below) to prevent reconciliation loops.

## Single-File Pattern

For apps with no local supporting resources (no ExternalSecrets, no local
Ingress, no extra manifests), use a single file `apps/<app-name>.yaml`
instead of a directory. The root Application discovers all YAML in `apps/`,
so standalone files are picked up automatically without an entry in
`root.yaml`. Still update the `root.yaml` comment header to document the
wave assignment.

Example: `apps/anthropic-oauth-proxy.yaml` — its Kubernetes resources live
in `tailnet-microservices/k8s` and are pulled via Kustomize.

## Web UI Exposure (Required)

Any application with a web UI must include a Tailscale Ingress. Do not
deploy web UIs cluster-internal only.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <app>-tailscale
  namespace: <app-namespace>
spec:
  ingressClassName: tailscale
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <frontend-service>
                port:
                  number: 80
```

If the Helm chart creates its own Ingress, disable it
(`ingress.enabled: false` in values) and use a local Tailscale Ingress
manifest instead. See `tailscale-networking.md` for exposure details and
`troubleshooting.md` for related failure modes.

## ExternalSecrets Integration

Secrets flow from Infisical (project `mothership-s0-ew`, prod environment)
through External Secrets Operator. Each secrets path has its own
ClusterSecretStore in `apps/external-secrets/clustersecretstore.yaml`:

| ClusterSecretStore | Infisical path |
|---|---|
| `infisical-tailscale` | `/tailscale-operator` |
| `infisical-netdata` | `/netdata` |
| `infisical-homarr` | `/homarr` |
| `infisical-longhorn` | `/longhorn` |

To add secrets for a new app:

1. Add secrets to Infisical under `/<app-name>` in `mothership-s0-ew`
   (prod environment).
2. Add a ClusterSecretStore to
   `apps/external-secrets/clustersecretstore.yaml`.
3. Create an `externalsecret.yaml` in the app's directory with
   `argocd.argoproj.io/sync-wave: "0"` so the Secret exists before the app
   syncs within its wave.

## ignoreDifferences for ESO

ESO injects default fields into ExternalSecrets that are not committed to
git, causing permanent OutOfSync. Add to the app's Application in
`root.yaml`:

```yaml
ignoreDifferences:
  - group: external-secrets.io
    kind: ExternalSecret
    jsonPointers:
      - /spec/data/0/remoteRef/conversionStrategy
      - /spec/data/0/remoteRef/decodingStrategy
      - /spec/data/0/remoteRef/metadataPolicy
```

Add entries for each data item index (0, 1, 2...), and include
`RespectIgnoreDifferences=true` in `syncOptions`. See `troubleshooting.md`
for the symptom-side description.

## Storage

Longhorn provides the default StorageClass; PVCs use `ReadWriteOnce`. For
data that needs backups, use the tiered StorageClasses
(`longhorn-critical` / `longhorn-important` / `longhorn-standard`) — see
`backup-storage.md`.

## Helm Chart Values

Always verify value keys against the chart's actual `values.yaml` before
setting them — several charts in this repo use non-obvious keys. Known
gotchas are recorded in `troubleshooting.md` under "Helm Chart Value
Gotchas".
