#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

required_tools=(
  actionlint
  gitleaks
  helm
  kubeconform
  lychee
  shellcheck
  shfmt
  terraform
  trivy
  uv
)

missing_tools=()
for tool_name in "${required_tools[@]}"; do
  if ! command -v "$tool_name" >/dev/null 2>&1; then
    missing_tools+=("$tool_name")
  fi
done

if ((${#missing_tools[@]} > 0)); then
  printf 'ERROR: missing CI tools: %s\n' "${missing_tools[*]}" >&2
  echo "Install Aqua and run: aqua install" >&2
  exit 1
fi

./scripts/check-sensitive-files.sh

terraform -chdir=terraform/infra init -backend=false -reconfigure -input=false
terraform -chdir=terraform/infra fmt -check -recursive
terraform -chdir=terraform/infra validate
terraform -chdir=terraform/platform init -backend=false -reconfigure -input=false
terraform -chdir=terraform/platform fmt -check -recursive
terraform -chdir=terraform/platform validate

render_dir=$(mktemp -d)
trap 'rm -rf "$render_dir"' EXIT

while IFS= read -r chart_file; do
  chart_dir=${chart_file%/Chart.yaml}
  release_name=$(basename "$chart_dir")
  helm lint "$chart_dir"
  helm template "$release_name" "$chart_dir" \
    --set gitOpsRepoUrl=https://github.com/j4v3l/proxmox-talos-lab.git \
    >"$render_dir/${release_name}.yaml"
done < <(find terraform/platform/charts gitops -name Chart.yaml -print | sort)

kubeconform \
  -strict \
  -summary \
  -ignore-missing-schemas \
  "$render_dir"

shellcheck scripts/*.sh
shfmt -d -i 2 -ci scripts/*.sh
uvx --from yamllint==1.37.1 yamllint .
actionlint
gitleaks git --redact --no-banner
trivy config --exit-code 1 --severity HIGH,CRITICAL --skip-version-check .
lychee --no-progress --exclude-path .git --exclude-path .terraform '**/*.md'
