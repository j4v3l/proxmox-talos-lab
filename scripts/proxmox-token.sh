#!/usr/bin/env bash
set -euo pipefail

proxmox_host=${PROXMOX_HOST:-192.168.0.119}
proxmox_ssh_user=${PROXMOX_SSH_USER:-root}
token_user=${TOKEN_USER:-terraform@pve}
token_id=${TOKEN_ID:-talos-production}
role_name=${ROLE_NAME:-TerraformTalos}
out_file=${OUT_FILE:-_out/proxmox.env}
rotate_token=${ROTATE_PROXMOX_TOKEN:-false}

for required_command in ssh jq; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'missing command: %s\n' "$required_command" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$out_file")"

role_privileges=(
  Datastore.AllocateSpace
  Datastore.Audit
  SDN.Use
  Sys.Audit
  VM.Allocate
  VM.Audit
  VM.Clone
  VM.Config.CDROM
  VM.Config.Cloudinit
  VM.Config.CPU
  VM.Config.Disk
  VM.Config.HWType
  VM.Config.Memory
  VM.Config.Network
  VM.Config.Options
  VM.Migrate
  VM.PowerMgmt
)
privilege_string="${role_privileges[*]}"

remote_script=$(printf '%q ' \
  "$token_user" \
  "$token_id" \
  "$role_name" \
  "$privilege_string" \
  "$rotate_token")

json=$(
  ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
    "${proxmox_ssh_user}@${proxmox_host}" \
    "bash -s -- ${remote_script}" <<'REMOTE'
set -euo pipefail
token_user=$1
token_id=$2
role_name=$3
privilege_string=$4
rotate_token=$5

pveum role modify "$role_name" --privs "$privilege_string" 2>/dev/null ||
  pveum role add "$role_name" --privs "$privilege_string"
pveum user modify "$token_user" --enable 1 2>/dev/null ||
  pveum user add "$token_user" --enable 1 --comment "Terraform production automation"
pveum acl modify / --user "$token_user" --role "$role_name" --propagate 1

if pveum user token list "$token_user" --output-format json |
  grep -Eq "\"tokenid\"[[:space:]]*:[[:space:]]*\"${token_id}\""; then
  if [ "$rotate_token" != "true" ]; then
    echo "Token already exists. Set ROTATE_PROXMOX_TOKEN=true to rotate it." >&2
    exit 1
  fi
  pveum user token remove "$token_user" "$token_id"
fi

pveum user token add "$token_user" "$token_id" \
  --privsep 1 \
  --comment "Terraform Talos production" \
  --output-format json
pveum acl modify / --token "${token_user}!${token_id}" --role "$role_name" --propagate 1
REMOTE
)

token_value=$(printf '%s\n' "$json" | jq -r '.value // empty')
if [[ -z "$token_value" ]]; then
  echo "could not parse Proxmox token value" >&2
  exit 1
fi

umask 077
{
  printf "export PROXMOX_VE_API_TOKEN='%s!%s=%s'\n" "$token_user" "$token_id" "$token_value"
  printf "export PROXMOX_VE_ENDPOINT='https://%s:8006/'\n" "$proxmox_host"
} >"$out_file"

printf 'Wrote privilege-separated Proxmox token environment to %s\n' "$out_file"
printf 'Trust the Proxmox CA locally and keep proxmox_insecure=false.\n'
