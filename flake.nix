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
          runtimeInputs = with pkgs; [ yq-go ];
          text = ''
            echo "Creating prod-argocd namespace..."
            kubectl create namespace prod-argocd --dry-run=client -o yaml | kubectl apply -f -
            
            echo "Installing ArgoCD with namespace override..."
            TMPDIR=$(mktemp -d)
            trap 'rm -rf "$TMPDIR"' EXIT
            
            cp -r apps/argocd "$TMPDIR/"
            yq eval '.namespace = "prod-argocd"' -i "$TMPDIR/argocd/overlays/prod/kustomization.yaml"
            
            kubectl kustomize --enable-helm "$TMPDIR/argocd/overlays/prod" | kubectl apply -f -
            
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
            echo "Get admin password: kubectl get secret argocd-initial-admin-secret -n prod-argocd -o jsonpath=\"{.data.password}\" | base64 -d"
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
            kubernetes-helm
            kubernetes-helmPlugins.helm-diff
            kubernetes-helmPlugins.helm-secrets
            kubernetes-helmPlugins.helm-s3
            kubernetes-helmPlugins.helm-git
            bootstrap
          ];
          shellHook = ''
            echo "Bootstrap scripts available:"
            echo "  bootstrap - Bootstrap ArgoCD with ApplicationSet"
          '';
        };
      }
    );
}
