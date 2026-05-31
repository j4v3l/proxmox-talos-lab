#!/usr/bin/env bash
set -euo pipefail

PROXMOX_HOST="${PROXMOX_HOST:-192.168.0.119}"
PROXMOX_SSH_USER="${PROXMOX_SSH_USER:-root}"
PROXMOX_NODE="${PROXMOX_NODE:-pve}"
OPNSENSE_HOST="${OPNSENSE_HOST:-192.168.80.1}"
BRIDGE="${BRIDGE:-vmbr0}"
VLAN_ID="${VLAN_ID:-80}"
VM_DATASTORE="${VM_DATASTORE:-local-lvm}"
MIN_AVAILABLE_RAM_GIB="${MIN_AVAILABLE_RAM_GIB:-30}"
MIN_DATASTORE_FREE_GIB="${MIN_DATASTORE_FREE_GIB:-400}"
REQUIRE_GITOPS_REPO="${REQUIRE_GITOPS_REPO:-true}"

VM_IDS=(810 811 812 813 814)
EXPECTED_IPS=(192.168.80.10 192.168.80.21 192.168.80.22 192.168.80.23 192.168.80.24 192.168.80.25 192.168.80.30)

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
required_ram_mib=$((MIN_AVAILABLE_RAM_GIB * 1024))
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

if [ "${REQUIRE_GITOPS_REPO}" = "true" ] && [ ! -f "terraform/platform/lab.auto.tfvars" ] && [ -z "${GITOPS_REPO_URL:-}" ]; then
  fail "GitOps repo URL is not configured; copy terraform/platform/terraform.tfvars.example to terraform/platform/lab.auto.tfvars and set gitops_repo_url"
elif [ "${REQUIRE_GITOPS_REPO}" != "true" ]; then
  pass "GitOps repo URL check skipped for local smoke bootstrap"
else
  pass "GitOps repo configuration file or GITOPS_REPO_URL exists"
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
