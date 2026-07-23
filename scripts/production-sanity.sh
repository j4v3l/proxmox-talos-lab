#!/usr/bin/env bash
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
kubeconfig_path=${KUBECONFIG:-${repo_root}/_out/kubeconfig}
talosconfig_path=${TALOSCONFIG:-${repo_root}/_out/talosconfig}
lab_ca_file=${LAB_CA_FILE:-}
gateway_ip=${GATEWAY_IP:-192.168.80.30}
pihole_primary=${PIHOLE_PRIMARY_IP:-192.168.80.31}
pihole_secondary=${PIHOLE_SECONDARY_IP:-192.168.80.32}

failures=0
warnings=0

pass() {
  printf 'OK: %s\n' "$*"
}

warn() {
  warnings=$((warnings + 1))
  printf 'WARN: %s\n' "$*" >&2
}

fail() {
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

kubectl_cmd() {
  kubectl --kubeconfig "$kubeconfig_path" --request-timeout=15s "$@"
}

for required_command in curl dig helm jq just kubectl talosctl terraform; do
  if command -v "$required_command" >/dev/null 2>&1; then
    pass "found command: $required_command"
  else
    fail "missing command: $required_command"
  fi
done

if (cd "$repo_root" && just validate && just render-checks); then
  pass "repository validation and rendering pass"
else
  fail "repository validation or rendering failed"
fi

if [[ ! -f "$kubeconfig_path" ]]; then
  fail "kubeconfig not found at $kubeconfig_path"
else
  node_failures=$(kubectl_cmd get nodes -o json 2>/dev/null | jq -r '
    .items[]
    | select((.status.conditions[] | select(.type == "Ready").status) != "True")
    | .metadata.name')
  if [[ -z "$node_failures" ]]; then
    pass "all Kubernetes nodes are Ready"
  else
    fail "non-Ready nodes: $node_failures"
  fi

  unhealthy_pods=$(kubectl_cmd get pods -A -o json 2>/dev/null | jq -r '
    .items[]
    | select(.status.phase != "Running" and .status.phase != "Succeeded")
    | "\(.metadata.namespace)/\(.metadata.name):\(.status.phase)"')
  if [[ -z "$unhealthy_pods" ]]; then
    pass "all pods are Running or Succeeded"
  else
    fail "unhealthy pods: $unhealthy_pods"
  fi

  oom_count=$(kubectl_cmd get pods -A -o json 2>/dev/null | jq '
    [.items[].status.containerStatuses[]? | select(.lastState.terminated.reason == "OOMKilled")] | length')
  if [[ ${oom_count:-1} -eq 0 ]]; then
    pass "no container has a recent OOMKilled state"
  else
    fail "$oom_count containers have OOMKilled history"
  fi

  bad_apps=$(kubectl_cmd -n argocd get applications.argoproj.io -o json 2>/dev/null | jq -r '
    .items[]
    | select((.status.sync.status // "Unknown") != "Synced" or (.status.health.status // "Unknown") != "Healthy")
    | "\(.metadata.name):sync=\(.status.sync.status // "Unknown"),health=\(.status.health.status // "Unknown")"')
  if [[ -z "$bad_apps" ]]; then
    pass "all Argo CD Applications are Synced/Healthy"
  else
    fail "Argo applications need attention: $bad_apps"
  fi

  default_project_apps=$(kubectl_cmd -n argocd get applications.argoproj.io -o json 2>/dev/null | jq -r '
    [.items[] | select(.spec.project == "default") | .metadata.name] | join(",")')
  if [[ -z "$default_project_apps" ]]; then
    pass "no Application uses the default project"
  else
    fail "Applications use default project: $default_project_apps"
  fi

  tracking_method=$(kubectl_cmd -n argocd get configmap argocd-cm -o jsonpath='{.data.application\.resourceTrackingMethod}' 2>/dev/null)
  if [[ "$tracking_method" == "annotation" ]]; then
    pass "Argo resource tracking is annotation-based"
  else
    fail "Argo annotation tracking is not enabled"
  fi

  gateway_programmed=$(kubectl_cmd -n gateway-system get gateway shared-gateway -o json 2>/dev/null | jq -r '
    any(.status.conditions[]?; .type == "Programmed" and .status == "True")')
  if [[ "$gateway_programmed" == "true" ]]; then
    pass "Cilium shared Gateway is Programmed"
  else
    fail "shared Gateway is not Programmed"
  fi

  bad_volumes=$(kubectl_cmd -n longhorn-system get volumes.longhorn.io -o json 2>/dev/null | jq -r '
    .items[]
    | select((.status.robustness // "") != "healthy" or (.spec.numberOfReplicas // 0) < 2)
    | "\(.metadata.name):robustness=\(.status.robustness),replicas=\(.spec.numberOfReplicas)"')
  if [[ -z "$bad_volumes" ]]; then
    pass "all Longhorn volumes are healthy with at least two replicas"
  else
    fail "Longhorn volumes violate production policy: $bad_volumes"
  fi

  low_disks=$(kubectl_cmd -n longhorn-system get nodes.longhorn.io -o json 2>/dev/null | jq -r '
    .items[] as $node
    | $node.status.diskStatus | to_entries[]
    | select((.value.storageAvailable / .value.storageMaximum * 100) < 20)
    | "\($node.metadata.name)/\(.key)"')
  if [[ -z "$low_disks" ]]; then
    pass "Longhorn disks retain at least 20% free space"
  else
    fail "Longhorn disks below 20% free: $low_disks"
  fi

  if kubectl_cmd -n longhorn-system get recurringjobs.longhorn.io nightly-offsite >/dev/null 2>&1 &&
    kubectl_cmd -A get scheduledbackups.postgresql.cnpg.io >/dev/null 2>&1; then
    pass "Longhorn and CloudNativePG backup schedules exist"
  else
    fail "required off-host backup schedules are missing"
  fi
fi

for dns_ip in "$pihole_primary" "$pihole_secondary"; do
  if dig +time=2 +tries=1 "@$dns_ip" github.com A >/dev/null 2>&1 &&
    dig +tcp +time=2 +tries=1 "@$dns_ip" github.com A >/dev/null 2>&1; then
    pass "DNS works over UDP and TCP through $dns_ip"
  else
    fail "DNS failed through $dns_ip"
  fi
done

if [[ -z "$lab_ca_file" || ! -f "$lab_ca_file" ]]; then
  fail "LAB_CA_FILE must point to the trusted private root CA"
else
  for service in argocd auth git longhorn pihole pihole-secondary; do
    hostname="${service}.lab.home.arpa"
    status=$(curl --cacert "$lab_ca_file" -sS -o /dev/null -w '%{http_code}' \
      --connect-timeout 5 --max-time 15 \
      --resolve "${hostname}:443:${gateway_ip}" "https://${hostname}" 2>/dev/null || true)
    case "$status" in
      200 | 301 | 302 | 401 | 403) pass "trusted HTTPS responds for $hostname" ;;
      *) fail "trusted HTTPS failed for $hostname (HTTP ${status:-none})" ;;
    esac
  done
fi

if [[ -f "$talosconfig_path" ]]; then
  if TALOSCONFIG="$talosconfig_path" talosctl -n 192.168.80.21 -e 192.168.80.21 health \
    --control-plane-nodes 192.168.80.21,192.168.80.22,192.168.80.23 \
    --worker-nodes 192.168.80.24,192.168.80.25 >/dev/null 2>&1; then
    pass "Talos cluster health passes"
  else
    fail "Talos cluster health failed"
  fi
else
  fail "talosconfig not found at $talosconfig_path"
fi

if [[ ${OPNSENSE_CROWDSEC_VERIFIED:-false} == "true" ]]; then
  pass "OPNsense os-crowdsec verification acknowledged"
else
  fail "set OPNSENSE_CROWDSEC_VERIFIED=true only after verifying the official OPNsense plugin"
fi

printf '\nSanity check finished with %s failure(s) and %s warning(s).\n' "$failures" "$warnings"
((failures == 0))
