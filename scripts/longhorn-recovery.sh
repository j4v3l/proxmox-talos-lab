#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG:-${ROOT_DIR}/_out/kubeconfig}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${LONGHORN_RECOVERY_OUT_DIR:-${ROOT_DIR}/_out/longhorn-recovery/${STAMP}}"
ALLOW_MUTATION="${ALLOW_LONGHORN_MUTATION:-false}"

kubectl_cmd() {
  kubectl --kubeconfig "${KUBECONFIG_PATH}" --request-timeout=15s "$@"
}

write_resource() {
  local name="$1"
  shift

  printf 'Capturing %s\n' "${name}"
  kubectl_cmd "$@" >"${OUT_DIR}/${name}.yaml" 2>"${OUT_DIR}/${name}.err" || true
}

if [ ! -f "${KUBECONFIG_PATH}" ]; then
  printf 'kubeconfig not found at %s\n' "${KUBECONFIG_PATH}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

write_resource "longhorn-volumes" -n longhorn-system get volumes.longhorn.io -o yaml
write_resource "longhorn-nodes" -n longhorn-system get nodes.longhorn.io -o yaml
write_resource "longhorn-replicas" -n longhorn-system get replicas.longhorn.io -o yaml
write_resource "longhorn-engines" -n longhorn-system get engines.longhorn.io -o yaml
write_resource "longhorn-settings" -n longhorn-system get settings.longhorn.io -o yaml
write_resource "storage" get storageclass,pv,pvc -A -o yaml
write_resource "pods" get pods -A -o wide
write_resource "events" get events -A --sort-by=.lastTimestamp

kubectl_cmd -n longhorn-system get volumes.longhorn.io -o json | jq -r '
  ["volume","state","robustness","node","namespace","pvc","workloads"],
  (.items[]
    | [
        .metadata.name,
        (.status.state // ""),
        (.status.robustness // ""),
        (.status.currentNodeID // ""),
        (.status.kubernetesStatus.namespace // ""),
        (.status.kubernetesStatus.pvcName // ""),
        ((.status.kubernetesStatus.workloadsStatus // []) | map(.podName + ":" + .podStatus) | join(","))
      ])
  | @tsv' >"${OUT_DIR}/volume-summary.tsv"

kubectl_cmd -n longhorn-system get nodes.longhorn.io -o json | jq -r '
  ["node","disk","ready","schedulable","storageMaximum","storageAvailable","storageScheduled"],
  (.items[] as $node
    | ($node.status.diskStatus // {})
    | to_entries[]
    | [
        $node.metadata.name,
        .key,
        ((.value.conditions // [])[]? | select(.type == "Ready") | .status),
        ((.value.conditions // [])[]? | select(.type == "Schedulable") | .status),
        (.value.storageMaximum // 0),
        (.value.storageAvailable // 0),
        (.value.storageScheduled // 0)
      ])
  | @tsv' >"${OUT_DIR}/disk-summary.tsv"

faulted_count="$(awk -F '\t' 'NR > 1 && $3 != "healthy" { count++ } END { print count + 0 }' "${OUT_DIR}/volume-summary.tsv")"

cat >"${OUT_DIR}/README.md" <<EOF
# Longhorn Recovery Capture ${STAMP}

This directory contains a read-only capture of the current Longhorn, PVC, pod, and event state.

Start with:

\`\`\`bash
column -t -s \$'\\t' "${OUT_DIR}/volume-summary.tsv"
column -t -s \$'\\t' "${OUT_DIR}/disk-summary.tsv"
\`\`\`

Recovery order:

1. Review every faulted volume and confirm whether the PVC data must be preserved.
2. Open Longhorn UI and try the built-in salvage flow for one volume at a time.
3. If salvage succeeds, wait for the workload pod to attach and start before moving to the next volume.
4. If salvage is not offered or fails, export/support-bundle the evidence before any delete/recreate action.
5. Delete or recreate PVCs only after explicit approval for each affected app.

This script does not delete PVCs, volumes, replicas, or workloads.
EOF

printf '\nWrote Longhorn recovery evidence to %s\n' "${OUT_DIR}"
printf 'Faulted or non-healthy Longhorn volumes: %s\n' "${faulted_count}"

if [ "${ALLOW_MUTATION}" != "true" ]; then
  printf '\nNo mutation attempted. Set ALLOW_LONGHORN_MUTATION=true only after reviewing the capture and choosing the exact Longhorn recovery action.\n'
  exit 0
fi

printf '\nALLOW_LONGHORN_MUTATION=true was set, but this script intentionally has no destructive fallback.\n' >&2
printf 'Use the Longhorn UI salvage/export workflow with the captured evidence, then rerun production sanity checks.\n' >&2
exit 2
