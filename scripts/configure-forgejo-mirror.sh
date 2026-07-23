#!/usr/bin/env bash
set -euo pipefail

forgejo_url=${FORGEJO_URL:-https://git.lab.home.arpa}
forgejo_owner=${FORGEJO_OWNER:-j4v3l}
repository_name=${REPOSITORY_NAME:-talos-apps}
github_repository=${GITHUB_REPOSITORY:-j4v3l/talos-apps}
repository_dir=${REPOSITORY_DIR:-/Users/jager/Documents/talos-apps}

required_variables=(
  FORGEJO_TOKEN
  GITHUB_MIRROR_TOKEN
)

for variable_name in "${required_variables[@]}"; do
  if [[ -z ${!variable_name:-} ]]; then
    printf 'ERROR: %s must be supplied outside the repository.\n' "$variable_name" >&2
    exit 1
  fi
done

for command_name in curl git jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'ERROR: missing command: %s\n' "$command_name" >&2
    exit 1
  fi
done

if [[ ! -d "$repository_dir/.git" ]]; then
  printf 'ERROR: %s is not a Git repository.\n' "$repository_dir" >&2
  exit 1
fi

work_dir=$(mktemp -d)
cleanup() {
  find "$work_dir" -depth -delete
}
trap cleanup EXIT
chmod 700 "$work_dir"

api() {
  curl \
    --fail-with-body \
    --silent \
    --show-error \
    --header "Authorization: token ${FORGEJO_TOKEN}" \
    --header 'Content-Type: application/json' \
    "$@"
}

repo_status=$(
  curl \
    --output "$work_dir/repository.json" \
    --write-out '%{http_code}' \
    --silent \
    --header "Authorization: token ${FORGEJO_TOKEN}" \
    "${forgejo_url}/api/v1/repos/${forgejo_owner}/${repository_name}"
)

case "$repo_status" in
  200) ;;
  404)
    jq -n \
      --arg name "$repository_name" \
      '{
        name: $name,
        private: true,
        default_branch: "main",
        auto_init: false,
        description: "Authoritative hybrid GitOps workload repository"
      }' >"$work_dir/create-repository.json"
    api \
      --request POST \
      --data-binary "@$work_dir/create-repository.json" \
      "${forgejo_url}/api/v1/user/repos" >"$work_dir/repository.json"
    ;;
  *)
    printf 'ERROR: Forgejo repository lookup returned HTTP %s.\n' "$repo_status" >&2
    cat "$work_dir/repository.json" >&2
    exit 1
    ;;
esac

cat >"$work_dir/askpass.sh" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' "${FORGEJO_GIT_USERNAME:?}" ;;
  *Password*) printf '%s\n' "${FORGEJO_GIT_PASSWORD:?}" ;;
  *) exit 1 ;;
esac
ASKPASS
chmod 700 "$work_dir/askpass.sh"

forgejo_remote="${forgejo_url}/${forgejo_owner}/${repository_name}.git"
if git -C "$repository_dir" remote get-url forgejo >/dev/null 2>&1; then
  git -C "$repository_dir" remote set-url forgejo "$forgejo_remote"
else
  git -C "$repository_dir" remote add forgejo "$forgejo_remote"
fi

FORGEJO_GIT_USERNAME="$forgejo_owner" \
  FORGEJO_GIT_PASSWORD="$FORGEJO_TOKEN" \
  GIT_ASKPASS="$work_dir/askpass.sh" \
  GIT_TERMINAL_PROMPT=0 \
  git -C "$repository_dir" push --set-upstream forgejo main

jq -n \
  '{
    rule_name: "main",
    branch_name: "main",
    apply_to_admins: true,
    enable_push: false,
    enable_push_whitelist: false,
    enable_merge_whitelist: false,
    enable_status_check: true,
    status_check_contexts: ["validate"],
    required_approvals: 0,
    dismiss_stale_approvals: true,
    block_on_rejected_reviews: true,
    block_on_official_review_requests: true,
    block_on_outdated_branch: true,
    require_signed_commits: true
  }' >"$work_dir/create-protection.json"

protection_status=$(
  curl \
    --output "$work_dir/protection.json" \
    --write-out '%{http_code}' \
    --silent \
    --header "Authorization: token ${FORGEJO_TOKEN}" \
    "${forgejo_url}/api/v1/repos/${forgejo_owner}/${repository_name}/branch_protections/main"
)

case "$protection_status" in
  200)
    jq 'del(.rule_name, .branch_name)' \
      "$work_dir/create-protection.json" >"$work_dir/edit-protection.json"
    api \
      --request PATCH \
      --data-binary "@$work_dir/edit-protection.json" \
      "${forgejo_url}/api/v1/repos/${forgejo_owner}/${repository_name}/branch_protections/main" \
      >"$work_dir/protection.json"
    ;;
  404)
    api \
      --request POST \
      --data-binary "@$work_dir/create-protection.json" \
      "${forgejo_url}/api/v1/repos/${forgejo_owner}/${repository_name}/branch_protections" \
      >"$work_dir/protection.json"
    ;;
  *)
    printf 'ERROR: Forgejo branch-protection lookup returned HTTP %s.\n' "$protection_status" >&2
    cat "$work_dir/protection.json" >&2
    exit 1
    ;;
esac

jq -n \
  --arg data "$GITHUB_MIRROR_TOKEN" \
  '{data: $data}' >"$work_dir/mirror-secret.json"
api \
  --request PUT \
  --data-binary "@$work_dir/mirror-secret.json" \
  "${forgejo_url}/api/v1/repos/${forgejo_owner}/${repository_name}/actions/secrets/GITHUB_MIRROR_TOKEN" \
  >"$work_dir/mirror-secret-response.json"

printf 'Forgejo %s/%s is authoritative and mirrors to GitHub %s branch mirror/forgejo-main.\n' \
  "$forgejo_owner" "$repository_name" "$github_repository"
printf 'Forgejo main requires signed commits and a successful validate check through protected merges.\n'
printf 'GitHub promotes that branch through a protected pull request; the mirror never pushes main.\n'
printf 'Rotate the GitHub mirror token after testing and keep it repository-scoped.\n'
