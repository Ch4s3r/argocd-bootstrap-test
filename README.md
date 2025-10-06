# ArgoCD Bootstrap

GitOps setup for bootstrapping ArgoCD with automatic application discovery.

## Prerequisites

- Nix with flakes enabled
- Running Kubernetes cluster
- kubectl configured

## Quick Start

```bash
# Enter Nix shell
nix develop

# Bootstrap ArgoCD
bootstrap

# Access UI (get password first)
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Access at https://localhost:8080 (user: `admin`)

## How It Works

Applications in `apps/*/overlays/*` are automatically discovered and deployed to `<app>-<env>` namespaces.

Example: `apps/hello-world/overlays/prod` → `hello-world-prod` namespace

## Add New Application

```bash
mkdir -p apps/my-app/{base,overlays/prod}
# Create kustomization.yaml files
# Commit and push - done!
```
