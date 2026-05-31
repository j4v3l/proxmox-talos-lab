resource "random_password" "rancher_bootstrap" {
  length  = 24
  special = false
}

resource "kubernetes_namespace_v1" "metallb_system" {
  metadata {
    name = "metallb-system"
    labels = merge(
      {
        name = "metallb-system"
      },
      local.privileged_pod_security_labels,
    )
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
    ]
  }
}

resource "kubernetes_namespace_v1" "longhorn_system" {
  metadata {
    name = "longhorn-system"
    labels = merge(
      {
        name = "longhorn-system"
      },
      local.privileged_pod_security_labels,
    )
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
    ]
  }
}

resource "helm_release" "cilium" {
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_chart_version

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      k8sServiceHost       = var.cluster_vip
      k8sServicePort       = "6443"
      kubeProxyReplacement = "false"
      ipam = {
        mode = "kubernetes"
      }
      cgroup = {
        autoMount = {
          enabled = false
        }
        hostRoot = "/sys/fs/cgroup"
      }
      securityContext = {
        capabilities = {
          ciliumAgent = [
            "CHOWN",
            "KILL",
            "NET_ADMIN",
            "NET_RAW",
            "IPC_LOCK",
            "SYS_ADMIN",
            "SYS_RESOURCE",
            "DAC_OVERRIDE",
            "FOWNER",
            "SETGID",
            "SETUID",
          ]
          cleanCiliumState = [
            "NET_ADMIN",
            "SYS_ADMIN",
            "SYS_RESOURCE",
          ]
        }
      }
      operator = {
        replicas = 1
      }
    }),
  ]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      crds = {
        enabled = true
      }
    }),
  ]

  depends_on = [
    helm_release.cilium,
  ]
}

resource "helm_release" "metallb" {
  name       = "metallb"
  namespace  = kubernetes_namespace_v1.metallb_system.metadata[0].name
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = var.metallb_chart_version

  wait    = true
  timeout = 600

  depends_on = [
    helm_release.cilium,
    kubernetes_namespace_v1.metallb_system,
  ]
}

resource "helm_release" "metallb_config" {
  name      = "metallb-config"
  namespace = "metallb-system"
  chart     = "${path.module}/charts/metallb-config"

  wait    = true
  timeout = 300

  values = [
    yamlencode({
      addresses = var.metallb_address_pool
    }),
  ]

  depends_on = [
    helm_release.metallb,
  ]
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      controller = {
        replicaCount = 2
        ingressClassResource = {
          default = true
        }
        service = {
          type                  = "LoadBalancer"
          loadBalancerIP        = var.ingress_load_balancer_ip
          externalTrafficPolicy = "Local"
        }
      }
    }),
  ]

  depends_on = [
    helm_release.metallb_config,
  ]
}

resource "helm_release" "argocd" {
  name             = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      configs = {
        params = {
          "server.insecure" = true
        }
      }
      server = {
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          hostname         = var.argocd_hostname
        }
      }
    }),
  ]

  depends_on = [
    helm_release.ingress_nginx,
  ]
}

resource "helm_release" "argocd_root_app" {
  count = var.gitops_repo_url == "" ? 0 : 1

  name      = "argocd-root-app"
  namespace = "argocd"
  chart     = "${path.module}/charts/argocd-root-app"

  wait    = true
  timeout = 300

  values = [
    yamlencode({
      gitOpsRepoUrl  = var.gitops_repo_url
      gitOpsRevision = var.gitops_revision
    }),
  ]

  depends_on = [
    helm_release.argocd,
  ]
}

resource "helm_release" "longhorn" {
  count = var.gitops_repo_url == "" ? 1 : 0

  name       = "longhorn"
  namespace  = kubernetes_namespace_v1.longhorn_system.metadata[0].name
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = var.longhorn_chart_version

  wait    = true
  timeout = 900

  values = [
    yamlencode({
      preUpgradeChecker = {
        jobEnabled = false
      }
      persistence = {
        defaultClass             = true
        defaultClassReplicaCount = 2
        reclaimPolicy            = "Delete"
      }
      defaultSettings = {
        defaultDataPath                         = "/var/mnt/longhorn"
        defaultReplicaCount                     = 2
        storageMinimalAvailablePercentage       = 10
        storageReservedPercentageForDefaultDisk = 10
        upgradeChecker                          = false
      }
      longhornManager = {
        nodeSelector = {
          "longhorn.io/storage" = "true"
        }
      }
      longhornDriver = {
        nodeSelector = {
          "longhorn.io/storage" = "true"
        }
      }
      longhornUI = {
        replicas = 1
        nodeSelector = {
          "longhorn.io/storage" = "true"
        }
      }
      ingress = {
        enabled          = true
        ingressClassName = "nginx"
        host             = "longhorn.192.168.80.30.sslip.io"
      }
    }),
  ]

  depends_on = [
    helm_release.ingress_nginx,
    kubernetes_namespace_v1.longhorn_system,
  ]
}

resource "helm_release" "whoami" {
  count = var.gitops_repo_url == "" ? 1 : 0

  name             = "whoami"
  namespace        = "lab"
  create_namespace = true
  chart            = "${path.module}/charts/whoami"

  wait    = true
  timeout = 300

  depends_on = [
    helm_release.ingress_nginx,
  ]
}

resource "helm_release" "rancher" {
  name             = "rancher"
  namespace        = "cattle-system"
  create_namespace = true
  repository       = "https://releases.rancher.com/server-charts/latest"
  chart            = "rancher"
  version          = var.rancher_chart_version

  wait    = true
  timeout = 900

  values = [
    yamlencode({
      hostname          = var.rancher_hostname
      bootstrapPassword = local.rancher_bootstrap_password
      replicas          = 1
      ingress = {
        ingressClassName = "nginx"
        tls = {
          source = "rancher"
        }
      }
    }),
  ]

  depends_on = [
    helm_release.cert_manager,
    helm_release.ingress_nginx,
  ]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  wait    = true
  timeout = 300

  values = [
    yamlencode({
      args = [
        "--kubelet-insecure-tls",
      ]
    }),
  ]

  depends_on = [
    helm_release.cilium,
  ]
}
