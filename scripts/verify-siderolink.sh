#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${ROOT_DIR}/terraform/infra"
TALOSCONFIG_PATH="${TALOSCONFIG:-${ROOT_DIR}/_out/talosconfig}"

failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'OK: %s\n' "$*"
}

need_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "found command: $1"
  else
    fail "missing command: $1"
  fi
}

talos_get() {
  local node="$1"
  local endpoint="$2"
  local resource="$3"
  local output="${4:-yaml}"

  TALOSCONFIG="${TALOSCONFIG_PATH}" talosctl -n "${node}" -e "${endpoint}" get "${resource}" -o "${output}" 2>/dev/null || true
}

need_cmd jq
need_cmd rg
need_cmd talosctl
need_cmd terraform

if ! [ -f "${TALOSCONFIG_PATH}" ]; then
  fail "talosconfig not found at ${TALOSCONFIG_PATH}"
fi

if rg -q 'variable "siderolink_enabled"' "${INFRA_DIR}/variables.tf" &&
  rg -q 'kind       = "SideroLinkConfig"' "${INFRA_DIR}/locals.tf"; then
  pass "terraform/infra is wired for optional SideroLink config"
else
  fail "terraform/infra does not contain the expected SideroLink wiring"
fi

siderolink_enabled="$(terraform -chdir="${INFRA_DIR}" output -raw siderolink_enabled 2>/dev/null || printf 'false')"
siderolink_configured="$(terraform -chdir="${INFRA_DIR}" output -raw siderolink_configured 2>/dev/null || printf 'false')"
controlplane_ip="$(terraform -chdir="${INFRA_DIR}" output -json controlplane_ips | jq -r '.[0]')"
worker_ip="$(terraform -chdir="${INFRA_DIR}" output -json node_ips | jq -r '.[]' | tail -n 1)"

controlplane_config="$(talos_get "${controlplane_ip}" "${controlplane_ip}" siderolinkconfig)"
worker_config="$(talos_get "${worker_ip}" "${controlplane_ip}" siderolinkconfig)"
controlplane_status="$(talos_get "${controlplane_ip}" "${controlplane_ip}" siderolinkstatus)"
worker_status="$(talos_get "${worker_ip}" "${controlplane_ip}" siderolinkstatus)"

if [ "${siderolink_enabled}" = "true" ]; then
  pass "terraform state reports SideroLink enabled"

  if [ "${siderolink_configured}" = "true" ]; then
    pass "terraform state reports a configured Omni SideroLink URL"
  else
    fail "terraform state reports SideroLink enabled but not configured"
  fi

  if [ -n "${controlplane_config}" ]; then
    pass "control plane exposes a SideroLinkConfig resource"
  else
    fail "control plane does not expose a SideroLinkConfig resource"
  fi

  if [ -n "${worker_config}" ]; then
    pass "worker exposes a SideroLinkConfig resource"
  else
    fail "worker does not expose a SideroLinkConfig resource"
  fi

  if printf '%s\n' "${controlplane_status}" | grep -Eq 'connected:[[:space:]]*true'; then
    pass "control plane reports SideroLink connected"
  else
    fail "control plane does not report SideroLink connected"
  fi

  if printf '%s\n' "${worker_status}" | grep -Eq 'connected:[[:space:]]*true'; then
    pass "worker reports SideroLink connected"
  else
    fail "worker does not report SideroLink connected"
  fi

  link_name="$(printf '%s\n%s\n' "${controlplane_status}" "${worker_status}" | sed -n -E 's/.*link(_name|Name):[[:space:]]*"?([^"[:space:]]+)"?.*/\2/p' | head -n 1)"
  controlplane_links="$(talos_get "${controlplane_ip}" "${controlplane_ip}" links table)"
  controlplane_addresses="$(talos_get "${controlplane_ip}" "${controlplane_ip}" addresses table)"
  worker_links="$(talos_get "${worker_ip}" "${controlplane_ip}" links table)"
  worker_addresses="$(talos_get "${worker_ip}" "${controlplane_ip}" addresses table)"

  if [ -n "${link_name}" ]; then
    if printf '%s\n%s\n' "${controlplane_links}" "${worker_links}" | grep -Eq "(^|[[:space:]])${link_name}([[:space:]]|$)"; then
      pass "SideroLink interface ${link_name} is present on the node network state"
    else
      fail "SideroLink interface ${link_name} is not visible in Talos link state"
    fi

    if printf '%s\n%s\n' "${controlplane_addresses}" "${worker_addresses}" | grep -Eq "(^|[[:space:]])${link_name}([[:space:]]|$)"; then
      pass "SideroLink interface ${link_name} has an address in Talos address state"
    else
      fail "SideroLink interface ${link_name} does not have an address in Talos address state"
    fi
  else
    if printf '%s\n%s\n%s\n%s\n' "${controlplane_links}" "${worker_links}" "${controlplane_addresses}" "${worker_addresses}" | grep -Eiq 'sidero|wireguard|wg'; then
      pass "Talos network state shows an extra overlay link or address for SideroLink"
    else
      fail "Talos network state does not show an extra overlay link or address for SideroLink"
    fi
  fi
else
  pass "terraform state reports SideroLink disabled"

  if [ "${siderolink_configured}" = "false" ]; then
    pass "terraform state reports no active SideroLink config"
  else
    fail "terraform state reports SideroLink configured while disabled"
  fi

  if [ -z "${controlplane_config}${worker_config}" ]; then
    pass "Talos does not expose SideroLinkConfig resources while disabled"
  else
    fail "Talos still exposes SideroLinkConfig resources while disabled"
  fi

  if [ -z "${controlplane_status}${worker_status}" ]; then
    pass "Talos does not expose active SideroLinkStatus resources while disabled"
  else
    fail "Talos still exposes active SideroLinkStatus resources while disabled"
  fi
fi

if [ "${failures}" -gt 0 ]; then
  printf '\nSideroLink verification failed with %s issue(s).\n' "${failures}" >&2
  exit 1
fi

printf '\nSideroLink verification passed.\n'
