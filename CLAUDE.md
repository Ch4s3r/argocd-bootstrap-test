# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a GitOps infrastructure-as-code project that uses ArgoCD for Kubernetes application deployment. The architecture features automatic application discovery, PR preview environments, and encrypted secret management using SOPS/Age.

## Development Commands

### Environment Setup
```bash
# Enter Nix development environment (provides kubectl, helm, sops, age, etc.)
nix develop

# Bootstrap ArgoCD installation
bootstrap
```

### ArgoCD Access
```bash
# Get admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Then visit: https://localhost:8080
```

### Secret Management with SOPS
```bash
# Create and encrypt a new secret
sops -e -i apps/my-app/base/secret.enc.yaml

# Edit an encrypted secret
sops apps/my-app/base/secret.enc.yaml

# Generate new Age key (for initial setup)
age-keygen
```

### Testing Changes
```bash
# Verify Kustomize builds correctly
kubectl kustomize apps/my-app/overlays/prod

# Dry-run apply to check for issues
kubectl apply --dry-run=client -k apps/my-app/overlays/prod

# Check ArgoCD application status
kubectl get applications -n argocd
```

## Architecture

### GitOps Flow
1. Code changes pushed to repository
2. ArgoCD ApplicationSet detects changes via Git generators
3. Applications auto-sync to Kubernetes clusters
4. Kustomize processes overlays + Helm charts
5. KSOPS plugin decrypts SOPS-encrypted secrets during deployment

### Application Structure Pattern
```
apps/
  {app-name}/
    base/                    # Base Helm/Kustomize configuration
      kustomization.yaml     # Includes helmCharts or resources
      secret.enc.yaml        # SOPS-encrypted secrets (optional)
    overlays/
      prod/                  # Production environment config
        kustomization.yaml
      staging/               # Staging environment config (enables PR previews)
        kustomization.yaml
```

### Automatic Application Discovery
ArgoCD ApplicationSet (`apps/argocd/base/applicationset.yaml`) automatically discovers and deploys:
- Any app with `apps/*/overlays/*` structure
- Creates namespaces: `{env}-{app-name}` (e.g., `prod-hello-world`, `staging-hello-world`)
- No manual Application CRD creation needed

### PR Preview Environments
When a PR is opened, ArgoCD automatically creates preview environments (`apps/argocd/base/applicationset-pr-previews.yaml`):
- **Triggers**: Any GitHub PR + apps with `overlays/staging/` directory
- **Naming**: `pr-{number}-{app-name}` in namespace `pr-{number}-{app-name}`
- **Auto-cleanup**: Environments deleted when PR closes/merges
- **Base config**: Uses `overlays/staging/` as template with PR-specific patches

To enable PR previews for an app: create `apps/{app-name}/overlays/staging/` directory.

### Secret Management Architecture
- **SOPS + Age encryption**: Secrets encrypted at rest in Git (`.sops.yaml` config)
- **KSOPS plugin**: Integrated into ArgoCD repo-server for automatic decryption
- **Age keys**: Bootstrap script generates and configures keys in ArgoCD
- **Pattern**: KSOPS generator references encrypted `*.enc.yaml` files

Example KSOPS configuration:
```yaml
# kustomization.yaml
generators:
  - secret-generator.yaml

# secret-generator.yaml
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: example-secret-generator
  annotations:
    config.kubernetes.io/function: |
        exec:
          path: ksops
files:
  - secret.enc.yaml

# secret.enc.yaml (SOPS-encrypted)
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
stringData:
  password: ENC[AES256_GCM,data:...]
```

### Kustomize + Helm Integration
Apps use Helm charts via Kustomize's `helmCharts` feature:
```yaml
# kustomization.yaml
helmCharts:
  - name: podinfo
    repo: https://stefanprodan.github.io/podinfo
    version: 6.7.1
    releaseName: hello-world
    namespace: prod-hello-world
    valuesInline:
      replicaCount: 2
```

When updating Helm chart versions, use Kustomize patches to replace the version in `kustomization.yaml` (see `apps/argocd/base/kustomization.yaml` for examples).

## Important Patterns

### Adding a New Application
1. Create directory structure: `apps/{app-name}/base/` and `apps/{app-name}/overlays/{env}/`
2. Add Helm chart or Kubernetes resources to `base/kustomization.yaml`
3. Configure environment-specific settings in overlay `kustomization.yaml`
4. ArgoCD will automatically discover and deploy (no manual app creation needed)

### Updating Helm Chart Versions
When Renovate creates PRs to update Helm chart versions:
- Updates are applied via Kustomize patches in `apps/argocd/base/kustomization.yaml`
- Pattern: `replacements` section with `fieldPath: spec.version` targeting helmChart

### Working with Encrypted Secrets
- Always encrypt secrets before committing: `sops -e -i path/to/secret.enc.yaml`
- Never commit unencrypted secrets to the repository
- KSOPS requires the generator pattern - create a `secret-generator.yaml` referencing your encrypted files
- Reference the generator in `kustomization.yaml` generators section
- Age public key is configured in `.sops.yaml`

### Namespace Management
- Namespaces are automatically created by ArgoCD ApplicationSet
- Convention: `{environment}-{app-name}` or `pr-{number}-{app-name}`
- No manual namespace creation needed

## Tools and Dependencies

- **Nix flakes**: Reproducible development environment
- **kubectl**: Kubernetes CLI
- **helm**: Helm package manager
- **sops**: Secret encryption
- **age**: Encryption key management
- **Renovate**: Automated dependency updates (configured in `renovate.json`)

## Documentation References

- Main README: `README.md`
- PR Previews: `docs/PR-PREVIEWS.md`
