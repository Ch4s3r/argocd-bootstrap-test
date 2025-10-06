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

Applications in `apps/*/overlays/*` are automatically discovered and deployed to `<env>-<app>` namespaces.

Example: `apps/hello-world/overlays/prod` → `prod-hello-world` namespace

## Secrets Management with SOPS

This setup includes [SOPS](https://github.com/mozilla/sops) with [age](https://github.com/FiloSottile/age) encryption for secure secret management.

The bootstrap script automatically:
- Generates an age encryption key
- Configures ArgoCD to decrypt secrets
- Updates `.sops.yaml` with your public key

See [docs/SOPS.md](docs/SOPS.md) for detailed documentation.

### Quick Example

```bash
# Encrypt a secret
sops -e -i apps/my-app/base/secret.enc.yaml

# Edit encrypted secret
sops apps/my-app/base/secret.enc.yaml
```

## Add New Application

```bash
mkdir -p apps/my-app/{base,overlays/prod}
# Create kustomization.yaml files
# Commit and push - done!
```
