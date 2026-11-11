# Files

- [ArgoCD reconciliation and promotion boundaries](reconciliation.md) - How the root and nested ArgoCD Applications reconcile the cluster, order dependencies, divide drift ownership, and preserve manual promotion gates. Explains the separate deletion risks of pruning, Application finalizers, and storage reclamation.
- [Dashboard, telemetry, and LLM workload contracts](workload-services.md) - Runtime state, secrets, network dependencies, and upgrade hazards for Homarr, Netdata, Phoenix, and the externally owned Anthropic OAuth proxy. Separates declared configuration from historical observations and planned authorization controls.
