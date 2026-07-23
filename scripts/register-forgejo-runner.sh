#!/usr/bin/env bash
set -euo pipefail

runner_host=${RUNNER_HOST:-ops@192.168.80.34}
forgejo_url=${FORGEJO_URL:-https://git.lab.home.arpa}
runner_name=${RUNNER_NAME:-talos-apps-runner}

if [[ -z ${FORGEJO_RUNNER_TOKEN:-} ]]; then
  echo "ERROR: set FORGEJO_RUNNER_TOKEN to a repository-scoped, single-use registration token" >&2
  exit 1
fi

ssh "$runner_host" sudo -u forgejo-runner \
  env HOME=/var/lib/forgejo-runner XDG_RUNTIME_DIR=/run/forgejo-runner \
  /usr/local/bin/forgejo-runner register \
  --config /etc/forgejo-runner.yaml \
  --no-interactive \
  --instance "$forgejo_url" \
  --token "$FORGEJO_RUNNER_TOKEN" \
  --name "$runner_name"

ssh "$runner_host" sudo systemctl enable --now forgejo-runner.service
unset FORGEJO_RUNNER_TOKEN

echo "Runner registered. Revoke the single-use registration token in Forgejo."
