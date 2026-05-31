locals {
  rancher_bootstrap_password = coalesce(var.rancher_bootstrap_password, random_password.rancher_bootstrap.result)

  privileged_pod_security_labels = {
    "pod-security.kubernetes.io/enforce" = "privileged"
    "pod-security.kubernetes.io/audit"   = "privileged"
    "pod-security.kubernetes.io/warn"    = "privileged"
  }
}
