#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="${ROOT_DIR}/terraform/infra"
TALOSCONFIG_PATH="${TALOSCONFIG:-${ROOT_DIR}/_out/talosconfig}"
PROXMOX_HOST="${PROXMOX_HOST:-192.168.0.119}"
PROXMOX_SSH_USER="${PROXMOX_SSH_USER:-root}"

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

remote() {
  ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "${PROXMOX_SSH_USER}@${PROXMOX_HOST}" "$@"
}

need_cmd jq
need_cmd rg
need_cmd ssh
need_cmd talosctl
need_cmd terraform

if ! [ -f "${TALOSCONFIG_PATH}" ]; then
  fail "talosconfig not found at ${TALOSCONFIG_PATH}"
fi

if rg -q 'bios\s*=\s*var\.secure_boot_enabled \? "ovmf" : "seabios"' "${INFRA_DIR}/main.tf" &&
  rg -q 'dynamic "efi_disk"' "${INFRA_DIR}/main.tf" &&
  rg -q 'urls\.iso_secureboot' "${INFRA_DIR}/locals.tf" &&
  rg -q 'urls\.installer_secureboot' "${INFRA_DIR}/locals.tf"; then
  pass "terraform/infra is wired for Secure Boot Talos assets and UEFI firmware"
else
  fail "terraform/infra does not contain the expected Secure Boot wiring"
fi

secure_boot_enabled="$(terraform -chdir="${INFRA_DIR}" output -raw secure_boot_enabled)"
efi_disk_datastore_id="$(terraform -chdir="${INFRA_DIR}" output -raw efi_disk_datastore_id)"
talos_iso_url="$(terraform -chdir="${INFRA_DIR}" output -raw talos_iso_url)"
talos_installer_image="$(terraform -chdir="${INFRA_DIR}" output -raw talos_installer_image)"

if [ "${secure_boot_enabled}" = "true" ]; then
  pass "terraform state reports Secure Boot enabled"
else
  fail "terraform state reports Secure Boot disabled"
fi

if printf '%s\n' "${talos_iso_url}" | grep -q 'secureboot'; then
  pass "Talos ISO URL is the Secure Boot variant"
else
  fail "Talos ISO URL is not the Secure Boot variant: ${talos_iso_url}"
fi

if printf '%s\n' "${talos_installer_image}" | grep -q 'installer-secureboot'; then
  pass "Talos installer image is the Secure Boot variant"
else
  fail "Talos installer image is not the Secure Boot variant: ${talos_installer_image}"
fi

vm_json="$(terraform -chdir="${INFRA_DIR}" output -json dhcp_reservations)"
controlplane_ip="$(terraform -chdir="${INFRA_DIR}" output -json controlplane_ips | jq -r '.[0]')"
worker_ip="$(terraform -chdir="${INFRA_DIR}" output -json node_ips | jq -r '.[]' | tail -n 1)"

for vm_id in $(printf '%s\n' "${vm_json}" | jq -r '.[].vm_id' | sort -n); do
  config="$(remote "qm config ${vm_id}")"

  if printf '%s\n' "${config}" | grep -q '^bios: ovmf$'; then
    pass "VM ${vm_id} uses OVMF"
  else
    fail "VM ${vm_id} does not use OVMF"
  fi

  if printf '%s\n' "${config}" | grep -q '^scsihw: virtio-scsi-pci$'; then
    pass "VM ${vm_id} uses VirtIO SCSI"
  else
    fail "VM ${vm_id} does not use VirtIO SCSI"
  fi

  efidisk_line="$(printf '%s\n' "${config}" | sed -n 's/^efidisk0: //p')"
  if [ -n "${efidisk_line}" ]; then
    pass "VM ${vm_id} has an EFI vars disk"
  else
    fail "VM ${vm_id} is missing efidisk0"
    continue
  fi

  if printf '%s\n' "${efidisk_line}" | grep -q 'efitype=4m'; then
    pass "VM ${vm_id} uses a 4m EFI vars disk"
  else
    fail "VM ${vm_id} does not use efitype=4m"
  fi

  if printf '%s\n' "${efidisk_line}" | grep -q 'pre-enrolled-keys=1'; then
    fail "VM ${vm_id} has pre-enrolled distro/Microsoft keys enabled"
  else
    pass "VM ${vm_id} is not using pre-enrolled distro/Microsoft keys"
  fi

  if printf '%s\n' "${efidisk_line}" | grep -q "${efi_disk_datastore_id}:"; then
    pass "VM ${vm_id} stores EFI vars on ${efi_disk_datastore_id}"
  else
    fail "VM ${vm_id} EFI vars disk is not on ${efi_disk_datastore_id}"
  fi

  if printf '%s\n' "${config}" | sed -n 's/^ide2: //p' | grep -q 'secureboot.iso'; then
    pass "VM ${vm_id} has the Secure Boot Talos ISO attached"
  else
    fail "VM ${vm_id} does not have the Secure Boot Talos ISO attached"
  fi
done

controlplane_state="$(TALOSCONFIG="${TALOSCONFIG_PATH}" talosctl -n "${controlplane_ip}" -e "${controlplane_ip}" get securitystate 2>&1 || true)"
if printf '%s\n' "${controlplane_state}" | grep -Eq 'securitystate.+true|SECUREBOOT.*true'; then
  pass "Talos control plane reports Secure Boot enabled at ${controlplane_ip}"
else
  fail "Talos control plane did not report Secure Boot enabled at ${controlplane_ip}: ${controlplane_state}"
fi

worker_state="$(TALOSCONFIG="${TALOSCONFIG_PATH}" talosctl -n "${worker_ip}" -e "${controlplane_ip}" get securitystate 2>&1 || true)"
if printf '%s\n' "${worker_state}" | grep -Eq 'securitystate.+true|SECUREBOOT.*true'; then
  pass "Talos worker reports Secure Boot enabled at ${worker_ip}"
else
  fail "Talos worker did not report Secure Boot enabled at ${worker_ip}: ${worker_state}"
fi

if [ "${failures}" -gt 0 ]; then
  printf '\nSecure Boot verification failed with %s issue(s).\n' "${failures}" >&2
  exit 1
fi

printf '\nSecure Boot verification passed.\n'
