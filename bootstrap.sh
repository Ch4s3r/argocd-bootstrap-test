#!/bin/zsh
set -e

# 1. Install ArgoCD via Helm chart using Kustomize
echo "Installing ArgoCD via Helm chart using Kustomize..."
kubectl kustomize --enable-helm apps/argocd | kubectl apply -f -

# 2. Wait for ArgoCD API server to be ready
echo "Waiting for ArgoCD API server to be ready..."
kubectl wait --namespace argocd --for=condition=Available deployment/argocd-server --timeout=180s

# 3. Apply ArgoCD ApplicationSet manifest (manages all apps in apps/)
echo "Applying ArgoCD ApplicationSet manifest..."
kubectl apply -f apps/applicationset.yaml

echo "Bootstrap complete!"
