{
  description = "ArgoCD bootstrap environment with Kubernetes and Helm tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        bootstrap = pkgs.writeShellApplication {
          name = "bootstrap";
          runtimeInputs = with pkgs; [ yq-go age sops ];
          text = ''
            echo "Creating prod-argocd namespace..."
            kubectl create namespace prod-argocd --dry-run=client -o yaml | kubectl apply -f -
            
            echo "Creating age secret for ArgoCD..."
            kubectl create secret generic sops-age \
              --from-file=keys.txt=/dev/stdin \
              --namespace=prod-argocd \
              --dry-run=client -o yaml < "$HOME/Library/Application Support/sops/age/keys.txt" | kubectl apply -f -
            
            echo "Installing ArgoCD with namespace override..."
            TMPDIR=$(mktemp -d)
            trap 'rm -rf "$TMPDIR"' EXIT
            
            cp -r apps/argocd "$TMPDIR/"
            yq eval '.namespace = "prod-argocd"' -i "$TMPDIR/argocd/overlays/prod/kustomization.yaml"
            
            kustomize build --enable-alpha-plugins --enable-exec "$TMPDIR/argocd/overlays/prod" | kubectl apply -f -
            
            echo "Waiting for ArgoCD server deployment to be created..."
            kubectl wait --for=condition=available --timeout=300s deployment -l app.kubernetes.io/name=argocd-server -n prod-argocd || true
            
            echo "Checking ArgoCD server status..."
            kubectl rollout status deployment -l app.kubernetes.io/name=argocd-server -n prod-argocd --timeout=300s
            
            echo "Waiting for CRDs to be ready..."
            sleep 5
            
            echo "Applying ApplicationSet..."
            kubectl apply -f apps/argocd/base/applicationset.yaml --namespace prod-argocd
            
            echo "Waiting for ApplicationSet to be created..."
            kubectl wait --for=jsonpath='{.metadata.name}'=all-apps applicationset/all-apps -n prod-argocd --timeout=60s
            
            echo "Bootstrap complete! Applications will be synced automatically."
            echo ""
            echo "Getting ArgoCD admin password..."
            PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n prod-argocd -o jsonpath="{.data.password}" | base64 -d)
            echo "$PASSWORD" | pbcopy
            echo "✓ Password copied to clipboard!"
            echo ""
            echo "Opening browser..."
            open https://localhost:8080
            echo ""
            echo "Starting port-forward to ArgoCD UI..."
            echo "Access ArgoCD at: https://localhost:8080"
            echo "Username: admin"
            echo "Password: (already in clipboard)"
            echo "Press Ctrl+C to stop port-forwarding"
            echo ""
            kubectl port-forward svc/argocd-server -n prod-argocd 8080:443
          '';
        };
      in
      {
        packages = {
          inherit bootstrap;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            uutils-coreutils-noprefix
            helmfile
            git
            curl
            kubectl
            kustomize-sops
            kubernetes-helm
            kubernetes-helmPlugins.helm-diff
            kubernetes-helmPlugins.helm-secrets
            kubernetes-helmPlugins.helm-s3
            kubernetes-helmPlugins.helm-git
            age
            sops
            bootstrap
          ];
          shellHook = ''
            echo "Bootstrap scripts available:"
            echo "  bootstrap - Bootstrap ArgoCD with ApplicationSet (includes age key setup)"
            echo ""
            echo "SOPS/age tools available:"
            echo "  age-keygen - Generate age keys"
            echo "  sops - Edit encrypted files"
          '';
        };
      }
    );
}
