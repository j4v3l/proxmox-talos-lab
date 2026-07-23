#!/usr/bin/env bash
set -euo pipefail

encrypted_identity=${1:-/Users/jager/Documents/Talos-Recovery/age/talos-apps-age-key.txt.gpg}
kubeconfig_path=${KUBECONFIG:-_out/kubeconfig}

if [[ ! -f "$encrypted_identity" ]]; then
  echo "ERROR: encrypted age identity not found: $encrypted_identity" >&2
  exit 1
fi

identity_dir=$(mktemp -d)
identity_file="${identity_dir}/keys.txt"
cleanup() {
  rm -f "$identity_file"
  rmdir "$identity_dir"
}
trap cleanup EXIT

umask 077
gpg --decrypt --output "$identity_file" "$encrypted_identity"
age-keygen -y "$identity_file" >/dev/null

kubectl --kubeconfig "$kubeconfig_path" -n argocd create secret generic argocd-sops-age \
  --from-file=keys.txt="$identity_file" \
  --dry-run=client \
  -o yaml |
  kubectl --kubeconfig "$kubeconfig_path" apply -f -

kubectl --kubeconfig "$kubeconfig_path" -n argocd rollout restart deployment/argo-cd-argocd-repo-server
echo "Injected the SOPS age identity directly into Argo CD without Terraform state."
