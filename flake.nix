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
          text = ''
            kubectl kustomize --enable-helm apps/argocd | kubectl apply -f -
            kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
            # kubectl apply -f apps/argocd/helmfile-applicationset.yaml
            # kubectl wait --for=jsonpath='{.metadata.name}'=all-apps applicationset/all-apps -n argocd
            kubectl apply -f helmfile-test/application.yaml
          '';
        };

        template = pkgs.writeShellApplication {
          name = "template";
          runtimeInputs = with pkgs; [ helmfile ];
          text = ''
            helmfile template
          '';
        };
      in
      {
        packages = {
          inherit bootstrap template;
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
            template
          ];
          shellHook = ''
            echo "Bootstrap scripts available:"
            echo "  bootstrap-helmfile - Bootstrap ArgoCD with helmfile ApplicationSet"
            echo "  bootstrap - Bootstrap ArgoCD with ApplicationSet"
            echo "  template - Run helmfile template"
          '';
        };
      }
    );
}
