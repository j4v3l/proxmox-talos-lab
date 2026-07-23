#!/usr/bin/env bash
set -euo pipefail

repositories=(
  j4v3l/proxmox-talos-lab
  j4v3l/talos-apps
)

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh is required." >&2
  exit 1
fi

gh auth status >/dev/null

for repository in "${repositories[@]}"; do
  gh api \
    --method PUT \
    --header 'Accept: application/vnd.github+json' \
    "repos/${repository}/branches/main/protection" \
    --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["validate"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": true
}
JSON

  gh api \
    --method POST \
    --header 'Accept: application/vnd.github+json' \
    "repos/${repository}/branches/main/protection/required_signatures" \
    >/dev/null

  gh api \
    --method PUT \
    --header 'Accept: application/vnd.github+json' \
    "repos/${repository}/vulnerability-alerts" \
    >/dev/null

  gh api \
    --method PUT \
    --header 'Accept: application/vnd.github+json' \
    "repos/${repository}/automated-security-fixes" \
    >/dev/null

  gh api \
    --method PATCH \
    --header 'Accept: application/vnd.github+json' \
    "repos/${repository}" \
    --input - <<'JSON'
{
  "security_and_analysis": {
    "secret_scanning": {
      "status": "enabled"
    },
    "secret_scanning_push_protection": {
      "status": "enabled"
    }
  }
}
JSON

  printf 'Protected %s main and enabled security updates plus secret push protection.\n' "$repository"
done
