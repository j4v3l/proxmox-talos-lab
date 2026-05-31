set shell := ["bash", "-euo", "pipefail", "-c"]

example_gitops_repo := "https://github.com/j4v3l/proxmox-talos-lab.git"

default:
    @just --list

preflight:
    ./scripts/preflight.sh

preflight-smoke:
    MIN_AVAILABLE_RAM_GIB=20 MIN_DATASTORE_FREE_GIB=40 REQUIRE_GITOPS_REPO=false ./scripts/preflight.sh

proxmox-token:
    ./scripts/proxmox-token.sh

init:
    cd terraform/infra && terraform init
    cd terraform/platform && terraform init

validate:
    cd terraform/infra && terraform fmt -check -recursive && terraform validate
    cd terraform/platform && terraform fmt -check -recursive && terraform validate

render-checks:
    helm lint terraform/platform/charts/metallb-config
    helm lint terraform/platform/charts/argocd-root-app --set gitOpsRepoUrl={{example_gitops_repo}}
    helm lint gitops/clusters/talos-lab --set gitOpsRepoUrl={{example_gitops_repo}}
    helm lint gitops/apps/argocd-repositories
    helm lint gitops/apps/platform-aliases
    helm lint gitops/apps/longhorn-lab-single
    helm lint gitops/apps/homarr-bootstrap
    helm lint gitops/apps/whoami
    helm lint gitops/apps/uptime-kuma
    helm lint gitops/apps/adguard-home
    helm lint gitops/apps/forgejo-runner
    helm lint terraform/platform/charts/whoami
    helm template metallb-config terraform/platform/charts/metallb-config --namespace metallb-system >/tmp/metallb-config.yaml
    helm template argocd-root-app terraform/platform/charts/argocd-root-app --namespace argocd --set gitOpsRepoUrl={{example_gitops_repo}} >/tmp/argocd-root-app.yaml
    helm template talos-lab gitops/clusters/talos-lab --set gitOpsRepoUrl={{example_gitops_repo}} >/tmp/talos-lab-apps.yaml
    helm template argocd-repositories gitops/apps/argocd-repositories --namespace argocd >/tmp/argocd-repositories.yaml
    helm template platform-aliases gitops/apps/platform-aliases --namespace argocd >/tmp/platform-aliases.yaml
    helm template longhorn-lab-single gitops/apps/longhorn-lab-single >/tmp/longhorn-lab-single.yaml
    helm template homarr-bootstrap gitops/apps/homarr-bootstrap --namespace homarr >/tmp/homarr-bootstrap.yaml
    helm template whoami gitops/apps/whoami --namespace lab >/tmp/gitops-whoami.yaml
    helm template uptime-kuma gitops/apps/uptime-kuma --namespace uptime-kuma >/tmp/uptime-kuma.yaml
    helm template adguard-home gitops/apps/adguard-home --namespace adguard-home >/tmp/adguard-home.yaml
    helm template forgejo-runner gitops/apps/forgejo-runner --namespace forgejo >/tmp/forgejo-runner.yaml
    helm template whoami terraform/platform/charts/whoami --namespace lab >/tmp/whoami.yaml

opnsense-check:
    @code="$(curl -ksS -o /dev/null -w '%{http_code}' --connect-timeout 8 https://192.168.80.1/ 2>/dev/null || true)"; if [[ "$code" =~ ^(200|301|302|401|403)$ ]]; then echo "OK: OPNsense HTTPS reachable at 192.168.80.1"; else echo "FAIL: OPNsense HTTPS unreachable at 192.168.80.1; HTTP status was ${code:-none}" >&2; exit 1; fi

tcp-check host port:
    @if nc -z -G 3 "{{host}}" "{{port}}" >/dev/null 2>&1 || nc -z -w 3 "{{host}}" "{{port}}" >/dev/null 2>&1; then echo "OK: {{host}}:{{port}} reachable"; else echo "FAIL: {{host}}:{{port}} unreachable" >&2; exit 1; fi

post-bootstrap-check:
    just tcp-check 192.168.80.10 6443
    just tcp-check 192.168.80.21 50000
    just tcp-check 192.168.80.22 50000
    just tcp-check 192.168.80.23 50000
    just tcp-check 192.168.80.24 50000
    just tcp-check 192.168.80.25 50000
    just tcp-check 192.168.80.30 80
    just tcp-check 192.168.80.30 443

post-bootstrap-smoke-check:
    just tcp-check 192.168.80.10 6443
    just tcp-check 192.168.80.103 50000
    just tcp-check 192.168.80.102 50000
    just tcp-check 192.168.80.101 50000
    just tcp-check 192.168.80.105 50000
    just tcp-check 192.168.80.104 50000
    just tcp-check 192.168.80.30 80
    just tcp-check 192.168.80.30 443

ingress-smoke-check:
    @for check in \
        "http whoami.192.168.80.30.sslip.io 80 200" \
        "http argocd.192.168.80.30.sslip.io 80 200" \
        "http longhorn.192.168.80.30.sslip.io 80 200" \
        "http rancher.192.168.80.30.sslip.io 80 308" \
        "https rancher.192.168.80.30.sslip.io 443 200"; do \
        set -- $check; \
        proto="$1"; host="$2"; port="$3"; expected="$4"; \
        code=$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 --resolve "$host:$port:192.168.80.30" "$proto://$host"); \
        if [ "$code" = "$expected" ]; then \
            echo "OK: $proto://$host -> $code"; \
        else \
            echo "FAIL: $proto://$host returned $code, expected $expected" >&2; \
            exit 1; \
        fi; \
    done
