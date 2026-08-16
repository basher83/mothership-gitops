# Tailscale Networking

Ingress (exposing cluster apps to the tailnet) and egress (pods reaching
tailnet hosts) patterns. For exposure failure modes see `troubleshooting.md`.

## Ingress: Exposing Web UIs

All web UIs are exposed via Tailscale Ingress class with automatic TLS on
port 443. The canonical manifest lives in `adding-applications.md`; a working
example is `apps/homarr/ingress.yaml`.

Notes:

- Prefer Ingress over `tailscale.com/expose` Service annotations — annotation
  exposure forwards the backend port (URL needs `:8080` suffixes) and some
  charts don't template Service annotations at all.
- First access after deploy can be slow while the TLS certificate provisions.
- Tailscale proxy pods need a privileged namespace; the pattern is carried in
  `apps/tailscale-operator/namespace.yaml`.

### Restricting ClusterIP Bypass

Tailscale Ingress controls the tailnet path, but it does not prevent an
ordinary cluster pod from calling the backend ClusterIP directly. Applications
that rely on Tailscale as their user-access boundary need an ingress
NetworkPolicy. `apps/radar/networkpolicy.yaml` is the canonical example.

Combine the `tailscale-operator` namespace selector and all four proxy pod
labels in the same `from` item so Kubernetes evaluates them as an AND:

```yaml
- namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: tailscale-operator
  podSelector:
    matchLabels:
      tailscale.com/managed: "true"
      tailscale.com/parent-resource: <ingress-name>
      tailscale.com/parent-resource-ns: <ingress-namespace>
      tailscale.com/parent-resource-type: ingress
```

The operator also adds an `app` label whose value is a generated UUID. Do not
commit that UUID as a policy identity. Revalidate the stable parent labels on a
live operator-created proxy after Tailscale Operator upgrades before changing
or copying the policy.

## Egress: Reaching Tailnet Hosts from Pods

For pods that need to reach Tailscale-connected hosts (e.g. Homarr →
Proxmox APIs), use the egress + DNS pattern. Working examples:
`apps/homarr/proxmox-egress.yaml`, `apps/longhorn/minio-egress.yaml`.

### 1. Egress Service

Creates a Tailscale proxy for the target host:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: proxmox-foxtrot
  namespace: homarr
  annotations:
    tailscale.com/tailnet-fqdn: foxtrot.tailfb3ea.ts.net
spec:
  type: ExternalName
  externalName: placeholder
```

The operator rewrites `externalName`; ArgoCD ignores that drift via an
`ignoreDifferences` entry for `/spec/externalName` on the owning Application.

### 2. DNSConfig

Deploys the Tailscale nameserver for MagicDNS resolution
(`apps/tailscale-operator/dnsconfig.yaml`):

```yaml
apiVersion: tailscale.com/v1alpha1
kind: DNSConfig
metadata:
  name: ts-dns
  namespace: tailscale-operator
spec:
  nameserver:
    image:
      repo: tailscale/k8s-nameserver
      tag: unstable
```

### 3. CoreDNS Forwarding

Forward `*.ts.net` queries to the nameserver (ClusterIP from
`kubectl get svc nameserver -n tailscale-operator`):

```text
ts.net:53 {
    forward . <nameserver-clusterip>
    cache 30
}
```

With this in place, pods connect using the real tailnet FQDN
(`https://foxtrot.tailfb3ea.ts.net`), preserving SNI for valid TLS with
Tailscale Serve.

### CoreDNS Persistence Caveat

Talos lifecycle events can overwrite CoreDNS config. This repo manages the
CoreDNS ConfigMap through the `coredns-tailscale` ArgoCD Application
(`apps/tailscale-operator/coredns/`) with self-heal enabled and prune
disabled — see `architecture.md` for the sync policy rationale.

If the `DNSConfig` resource is ever recreated, the nameserver ClusterIP may
change. Revalidate it before relying on the checked-in CoreDNS forwarding
target:

```bash
kubectl get svc nameserver -n tailscale-operator
```
