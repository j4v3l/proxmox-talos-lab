output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = "https://${var.cluster_vip}:6443"
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

