output "rancher_url" {
  description = "Rancher UI URL."
  value       = "http://${var.rancher_hostname}"
}

output "argocd_url" {
  description = "Argo CD UI URL."
  value       = "http://${var.argocd_hostname}"
}

output "ingress_ip" {
  description = "MetalLB IP assigned to ingress-nginx."
  value       = var.ingress_load_balancer_ip
}

output "rancher_bootstrap_password" {
  description = "Rancher bootstrap password. Stored in Terraform state."
  value       = local.rancher_bootstrap_password
  sensitive   = true
}

