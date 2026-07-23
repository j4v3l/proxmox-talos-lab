#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
cd "$repo_root"

forbidden_path_regex='(^|/)(tfplan[^/]*|[^/]*\.tfplan|[^/]*\.tfstate(\.[^/]*)?|terraform\.tfvars|[^/]*\.auto\.tfvars|kubeconfig|talosconfig|secrets?\.(ya?ml|json)|[^/]*\.sops\.dec\.[^/]*|age\.key|[^/]*\.agekey|credentials[^/]*)$'
tracked_paths=$(git ls-files)

if printf '%s\n' "$tracked_paths" | grep -E "$forbidden_path_regex" | grep -Ev '(\.example|\.sample|\.template)$'; then
  echo "ERROR: tracked sensitive artifact or generated credential file found" >&2
  exit 1
fi

if git grep -I -n -E -- \
  '-----BEGIN (OPENSSH|RSA|EC|DSA|PGP) PRIVATE KEY-----|AGE-SECRET-KEY-[A-Z0-9]+' \
  -- . \
  ':(exclude)*.example' \
  ':(exclude)*.sample' \
  ':(exclude)*.template'; then
  echo "ERROR: plaintext private key found" >&2
  exit 1
fi

if git ls-files | grep -E '(^|/)(tfplan[^/]*|[^/]*\.tfplan)$' >/dev/null; then
  echo "ERROR: Terraform plan binaries must never be tracked" >&2
  exit 1
fi

echo "Sensitive-file policy passed."
