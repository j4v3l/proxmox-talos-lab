set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

preflight:
    ./scripts/preflight.sh

proxmox-token:
    ./scripts/proxmox-token.sh

init-local:
    terraform -chdir=terraform/infra init -backend=false -reconfigure
    terraform -chdir=terraform/platform init -backend=false -reconfigure

init-backends:
    terraform -chdir=terraform/infra init -reconfigure -backend-config=../backend.s3.hcl -backend-config='key=infra/terraform.tfstate'
    terraform -chdir=terraform/platform init -reconfigure -backend-config=../backend.s3.hcl -backend-config='key=platform/terraform.tfstate'

validate:
    terraform -chdir=terraform/infra fmt -check -recursive
    terraform -chdir=terraform/infra validate
    terraform -chdir=terraform/platform fmt -check -recursive
    terraform -chdir=terraform/platform validate

render-checks:
    helm lint terraform/platform/charts/argocd-root-app
    helm lint gitops/clusters/talos-lab
    helm template argocd-root terraform/platform/charts/argocd-root-app >/tmp/argocd-root.yaml
    helm template talos-bootstrap gitops/clusters/talos-lab >/tmp/talos-bootstrap.yaml

ci:
    ./scripts/ci.sh

configure-pihole:
    ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/pihole.yaml

configure-forgejo-runner:
    ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/forgejo-runner.yaml

register-forgejo-runner:
    ./scripts/register-forgejo-runner.sh

bootstrap-sops-age recovery_file="/Users/jager/Documents/Talos-Recovery/age/talos-apps-age-key.txt.gpg":
    ./scripts/bootstrap-sops-age.sh "{{recovery_file}}"

production-sanity:
    ./scripts/production-sanity.sh

longhorn-recovery-capture:
    ./scripts/longhorn-recovery.sh

verify-secureboot:
    ./scripts/verify-secureboot.sh

verify-siderolink:
    ./scripts/verify-siderolink.sh

tcp-check host port:
    @if nc -z -G 3 "{{host}}" "{{port}}" >/dev/null 2>&1 || nc -z -w 3 "{{host}}" "{{port}}" >/dev/null 2>&1; then echo "OK: {{host}}:{{port}} reachable"; else echo "FAIL: {{host}}:{{port}} unreachable" >&2; exit 1; fi

post-bootstrap-check:
    just tcp-check 192.168.80.10 6443
    @for ip in 192.168.80.21 192.168.80.22 192.168.80.23 192.168.80.24 192.168.80.25; do just tcp-check "$ip" 50000; done
    just tcp-check 192.168.80.30 80
    just tcp-check 192.168.80.30 443
    just tcp-check 192.168.80.31 53
    just tcp-check 192.168.80.32 53
    just tcp-check 192.168.80.33 22

gateway-smoke-check:
    @for host in argocd auth git longhorn pihole pihole-secondary; do \
        code=$(curl --cacert "$LAB_CA_FILE" -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 --resolve "$host.lab.home.arpa:443:192.168.80.30" "https://$host.lab.home.arpa"); \
        case "$code" in 200|301|302|401|403) echo "OK: https://$host.lab.home.arpa -> $code" ;; *) echo "FAIL: https://$host.lab.home.arpa -> $code" >&2; exit 1 ;; esac; \
    done
