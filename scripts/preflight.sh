#!/usr/bin/env bash
set -euo pipefail

PROXMOX_HOST="${PROXMOX_HOST:-192.168.0.119}"
PROXMOX_SSH_USER="${PROXMOX_SSH_USER:-root}"
PROXMOX_NODE="${PROXMOX_NODE:-pve}"
OPNSENSE_HOST="${OPNSENSE_HOST:-192.168.80.1}"
BRIDGE="${BRIDGE:-vmbr0}"
VLAN_ID="${VLAN_ID:-80}"
VM_DATASTORE="${VM_DATASTORE:-talos-ssd}"
MIN_TOTAL_RAM_GIB="${MIN_TOTAL_RAM_GIB:-64}"
MIN_AVAILABLE_RAM_GIB="${MIN_AVAILABLE_RAM_GIB:-48}"
MIN_DATASTORE_FREE_GIB="${MIN_DATASTORE_FREE_GIB:-800}"
REQUIRE_GITOPS_REPO="${REQUIRE_GITOPS_REPO:-true}"

VM_IDS=(810 811 812 813 814 820 821)
EXPECTED_IPS=(192.168.80.10 192.168.80.21 192.168.80.22 192.168.80.23 192.168.80.24 192.168.80.25 192.168.80.30 192.168.80.31 192.168.80.32 192.168.80.33 192.168.80.34)

failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'OK: %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing command: $1"
  else
    pass "found command: $1"
  fi
}

remote() {
  ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "${PROXMOX_SSH_USER}@${PROXMOX_HOST}" "$@"
}

read_auto_tfvars_value() {
  local key="$1"
  local file
  local value=""
  local raw=""

  while IFS= read -r file; do
    raw="$(sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.+)$/\\1/p" "${file}" | tail -n 1)"
    if [ -n "${raw}" ]; then
      raw="${raw%%#*}"
      raw="$(printf '%s' "${raw}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      value="${raw}"
    fi
  done < <(find terraform/infra -maxdepth 1 -type f -name '*.auto.tfvars' -print | sort)

  printf '%s' "${value}"
}

dequote_tfvars_value() {
  local value="$1"

  if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "${value}"
  fi
}

extract_url_authority() {
  printf '%s' "$1" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]+).*$#\1#'
}

need_cmd ssh
need_cmd awk
need_cmd curl
need_cmd ping
need_cmd sed
need_cmd terraform
need_cmd talosctl
need_cmd kubectl
need_cmd helm

if remote "hostname >/dev/null"; then
  pass "SSH reachable: ${PROXMOX_SSH_USER}@${PROXMOX_HOST}"
else
  fail "cannot SSH to ${PROXMOX_SSH_USER}@${PROXMOX_HOST}"
fi

api_http_code="$(curl -ksS -o /dev/null -w '%{http_code}' --connect-timeout 8 "https://${PROXMOX_HOST}:8006/api2/json/version" 2>/dev/null || true)"
if printf '%s\n' "${api_http_code}" | grep -Eq '^(200|401|403)$'; then
  pass "Proxmox API reachable at https://${PROXMOX_HOST}:8006"
else
  fail "Proxmox API is not reachable at https://${PROXMOX_HOST}:8006; HTTP status was ${api_http_code:-none}"
fi

opnsense_http_code="$(curl -ksS -o /dev/null -w '%{http_code}' --connect-timeout 8 "https://${OPNSENSE_HOST}/" 2>/dev/null || true)"
if printf '%s\n' "${opnsense_http_code}" | grep -Eq '^(200|301|302|401|403)$'; then
  pass "OPNsense HTTPS reachable at https://${OPNSENSE_HOST}/"
else
  fail "OPNsense HTTPS is not reachable at https://${OPNSENSE_HOST}/; HTTP status was ${opnsense_http_code:-none}"
fi

if [ -n "${PROXMOX_VE_API_TOKEN:-}" ] || { [ -n "${PROXMOX_VE_USERNAME:-}" ] && [ -n "${PROXMOX_VE_PASSWORD:-}" ]; }; then
  pass "Proxmox provider credentials are present in the environment"
else
  warn "Proxmox provider credentials are not exported; terraform plan/apply will fail until PROXMOX_VE_API_TOKEN or PROXMOX_VE_USERNAME/PROXMOX_VE_PASSWORD is set"
fi

if remote "pvesh get /nodes/${PROXMOX_NODE}/status >/dev/null" >/dev/null 2>&1; then
  pass "Proxmox node exists: ${PROXMOX_NODE}"
else
  fail "Proxmox node not found or API unavailable through SSH: ${PROXMOX_NODE}"
fi

available_ram_mib="$(remote "free -m | awk '/^Mem:/ {print \$7}'" 2>/dev/null || printf '0')"
total_ram_mib="$(remote "free -m | awk '/^Mem:/ {print \$2}'" 2>/dev/null || printf '0')"
required_total_ram_mib=$((MIN_TOTAL_RAM_GIB * 1024))
required_ram_mib=$((MIN_AVAILABLE_RAM_GIB * 1024))
if [ "${total_ram_mib}" -ge "${required_total_ram_mib}" ]; then
  pass "total RAM is at least ${MIN_TOTAL_RAM_GIB} GiB"
else
  fail "installed RAM is too low: $((total_ram_mib / 1024)) GiB total, ${MIN_TOTAL_RAM_GIB} GiB required"
fi
if [ "${available_ram_mib}" -ge "${required_ram_mib}" ]; then
  pass "available RAM is at least ${MIN_AVAILABLE_RAM_GIB} GiB"
else
  fail "available RAM is too low: $((available_ram_mib / 1024)) GiB available, ${MIN_AVAILABLE_RAM_GIB} GiB required"
fi

datastore_avail_kib="$(remote "pvesm status --storage '${VM_DATASTORE}' | awk 'NR==2 {print \$6}'" 2>/dev/null || printf '0')"
datastore_avail_gib=$((datastore_avail_kib / 1024 / 1024))
if [ "${datastore_avail_gib}" -ge "${MIN_DATASTORE_FREE_GIB}" ]; then
  pass "${VM_DATASTORE} has at least ${MIN_DATASTORE_FREE_GIB} GiB free"
else
  fail "${VM_DATASTORE} is too full: ${datastore_avail_gib} GiB free, ${MIN_DATASTORE_FREE_GIB} GiB required"
fi

for vmid in "${VM_IDS[@]}"; do
  if remote "qm status ${vmid} >/dev/null 2>&1"; then
    fail "VMID ${vmid} already exists"
  else
    pass "VMID ${vmid} is unused"
  fi
done

bridge_vids="$(remote "pvesh get /nodes/${PROXMOX_NODE}/network --output-format json | sed -n 's/.*\"iface\":\"${BRIDGE}\".*\"bridge_vids\":\"\\([^\"]*\\)\".*/\\1/p'" 2>/dev/null || true)"
if [ -z "${bridge_vids}" ]; then
  bridge_vids="$(remote "awk '/iface ${BRIDGE} inet/{found=1} found && /bridge-vids/{for (i=2; i<=NF; i++) printf \"%s \", \$i; exit}' /etc/network/interfaces" 2>/dev/null || true)"
fi

if printf ' %s ' "${bridge_vids}" | grep -Eq " (2-4094|${VLAN_ID}) "; then
  pass "${BRIDGE} allows VLAN ${VLAN_ID}"
else
  fail "${BRIDGE} does not appear to allow VLAN ${VLAN_ID}; current bridge-vids: ${bridge_vids:-unknown}"
fi

if [ "${REQUIRE_GITOPS_REPO}" = "true" ] && [ ! -f "terraform/platform/lab.auto.tfvars" ] && [ -z "${APPS_REPO_URL:-}" ]; then
  fail "GitOps repositories are not configured; create terraform/platform/lab.auto.tfvars with bootstrap_repo_url and apps_repo_url"
elif [ "${REQUIRE_GITOPS_REPO}" != "true" ]; then
  pass "GitOps repo URL check skipped for local smoke bootstrap"
else
  pass "GitOps repo configuration file or GITOPS_REPO_URL exists"
fi

siderolink_enabled_raw="${SIDEROLINK_ENABLED:-$(read_auto_tfvars_value siderolink_enabled)}"
siderolink_api_url_raw="${SIDEROLINK_API_URL:-$(read_auto_tfvars_value siderolink_api_url)}"
siderolink_enabled="false"
siderolink_api_url=""

if [ -n "${siderolink_enabled_raw}" ] && [ "${siderolink_enabled_raw,,}" = "true" ]; then
  siderolink_enabled="true"
fi

if [ -n "${siderolink_api_url_raw}" ]; then
  siderolink_api_url="$(dequote_tfvars_value "${siderolink_api_url_raw}")"
fi

if [ "${siderolink_enabled}" = "true" ]; then
  if [ -z "${siderolink_api_url}" ]; then
    fail "SideroLink is enabled but siderolink_api_url is empty; set the full Omni SideroLink URL in terraform/infra/*.auto.tfvars or SIDEROLINK_API_URL"
  elif printf '%s\n' "${siderolink_api_url}" | grep -Eq '^https://[^[:space:]]+\?.*jointoken='; then
    pass "SideroLink URL looks like a full Omni SideroLink URL"
  else
    fail "siderolink_api_url must be a full https:// Omni SideroLink URL containing jointoken="
  fi

  if [ -n "${siderolink_api_url}" ]; then
    siderolink_authority="$(extract_url_authority "${siderolink_api_url}")"
    siderolink_http_code="$(curl -ksS -o /dev/null -w '%{http_code}' --connect-timeout 8 "https://${siderolink_authority}/" 2>/dev/null || true)"

    if printf '%s\n' "${siderolink_http_code}" | grep -Eq '^(200|301|302|401|403|404)$'; then
      pass "Omni SideroLink host reachable at https://${siderolink_authority}/"
    else
      fail "Omni SideroLink host is not reachable at https://${siderolink_authority}/; HTTP status was ${siderolink_http_code:-none}"
    fi
  fi
else
  pass "SideroLink disabled; Omni connectivity checks skipped"
fi

for ip in "${EXPECTED_IPS[@]}"; do
  if ping -c 1 -W 1 "${ip}" >/dev/null 2>&1; then
    warn "${ip} responds to ping; verify it is intentionally reserved for this lab before applying Terraform"
  fi
done

if [ "${failures}" -gt 0 ]; then
  printf '\nPreflight failed with %s issue(s). Fix them before terraform apply.\n' "${failures}" >&2
  exit 1
fi

printf '\nPreflight passed.\n'
