output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = "https://${var.cluster_vip}:6443"
}

output "secure_boot_enabled" {
  description = "Whether Talos Secure Boot is enabled for this cluster."
  value       = var.secure_boot_enabled
}

output "siderolink_enabled" {
  description = "Whether SideroLink is enabled for this cluster."
  value       = var.siderolink_enabled
}

output "siderolink_configured" {
  description = "Whether SideroLink is both enabled and has a non-empty Omni API URL configured."
  value       = nonsensitive(local.siderolink_configured)
}

output "efi_disk_datastore_id" {
  description = "Datastore used for the Talos EFI vars disks."
  value       = local.efi_disk_datastore_id
}

output "talos_iso_url" {
  description = "Talos boot ISO URL selected by the infra configuration."
  value       = local.talos_iso_url
}

output "talos_installer_image" {
  description = "Talos installer image selected by the infra configuration."
  value       = local.talos_installer_image
}

output "controlplane_ips" {
  description = "Talos control-plane node IPs."
  value       = local.controlplane_ips
}

output "node_ips" {
  description = "All Talos node IPs."
  value       = local.node_ips
}

output "kubeconfig_path" {
  description = "Generated kubeconfig path."
  value       = abspath(local_sensitive_file.kubeconfig.filename)
}

output "talosconfig_path" {
  description = "Generated talosconfig path."
  value       = abspath(local_sensitive_file.talosconfig.filename)
}

output "dhcp_reservations" {
  description = "MAC-to-IP reservations to create before apply."
  value = {
    for key, node in var.nodes : node.hostname => {
      mac_address = node.mac_address
      ip          = node.ip
      vm_id       = node.vm_id
    }
  }
}

output "service_vm_ips" {
  description = "Static service VM addresses."
  value = {
    for key, vm in var.service_vms : key => vm.ip
  }
}
