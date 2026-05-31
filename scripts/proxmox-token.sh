#!/usr/bin/env bash
set -euo pipefail

PROXMOX_HOST="${PROXMOX_HOST:-192.168.0.119}"
PROXMOX_SSH_USER="${PROXMOX_SSH_USER:-root}"
TOKEN_USER="${TOKEN_USER:-root@pam}"
TOKEN_ID="${TOKEN_ID:-terraform-talos}"
OUT_FILE="${OUT_FILE:-_out/proxmox.env}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing command: %s\n' "$1" >&2
    exit 1
  fi
}

need_cmd ssh
need_cmd jq

mkdir -p "$(dirname "${OUT_FILE}")"

json="$(
  ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "${PROXMOX_SSH_USER}@${PROXMOX_HOST}" \
    "pveum user token delete '${TOKEN_USER}' '${TOKEN_ID}' >/dev/null 2>&1 || true; pveum user token add '${TOKEN_USER}' '${TOKEN_ID}' --privsep 0 --comment 'Terraform Talos lab' --output-format json"
)"

token_value="$(printf '%s\n' "${json}" | jq -r '.value // empty')"
if [ -z "${token_value}" ]; then
  printf 'could not parse Proxmox token value from pveum output\n' >&2
  exit 1
fi

umask 077
cat >"${OUT_FILE}" <<EOF
export PROXMOX_VE_API_TOKEN='${TOKEN_USER}!${TOKEN_ID}=${token_value}'
EOF

printf 'Wrote Proxmox Terraform token environment to %s\n' "${OUT_FILE}"

