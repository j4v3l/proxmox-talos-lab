output "argocd_url" {
  description = "Argo CD LAN/VPN URL through the shared Cilium Gateway."
  value       = "https://argocd.${var.lab_base_domain}"
}

output "gateway_ip" {
  description = "Shared Cilium Gateway address."
  value       = var.gateway_load_balancer_ip
}

output "dns_ips" {
  description = "Primary and secondary Pi-hole addresses advertised by OPNsense."
  value = [
    var.pihole_primary_ip,
    var.pihole_secondary_ip,
  ]
}

output "forgejo_ssh_endpoint" {
  description = "Forgejo SSH endpoint."
  value       = "${var.forgejo_ssh_ip}:22"
}

output "gateway_api_version" {
  description = "Terraform-managed Gateway API CRD version."
  value       = var.gateway_api_version
}
