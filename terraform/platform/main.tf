data "http" "gateway_api_standard" {
  url = local.gateway_api_manifest_url
}

resource "terraform_data" "gateway_api_integrity" {
  input = sha256(data.http.gateway_api_standard.response_body)

  lifecycle {
    precondition {
      condition     = sha256(data.http.gateway_api_standard.response_body) == var.gateway_api_manifest_sha256
      error_message = "Gateway API manifest checksum mismatch; review the upstream release before changing the pinned checksum."
    }
  }
}

data "kubectl_file_documents" "gateway_api_standard" {
  content = data.http.gateway_api_standard.response_body
}

resource "kubectl_manifest" "gateway_api_standard" {
  for_each = data.kubectl_file_documents.gateway_api_standard.manifests

  yaml_body         = each.value
  server_side_apply = true
  force_conflicts   = false
  wait_for_rollout  = true
  validate_schema   = true

  depends_on = [
    terraform_data.gateway_api_integrity,
  ]
}

resource "helm_release" "cilium" {
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_chart_version

  atomic  = true
  wait    = true
  timeout = 900

  values = [
    yamlencode({
      k8sServiceHost       = "localhost"
      k8sServicePort       = "7445"
      kubeProxyReplacement = true
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
        replicas = 2
        prometheus = {
          enabled = true
        }
      }
      envoy = {
        enabled = true
        prometheus = {
          enabled = true
        }
      }
      gatewayAPI = {
        enabled    = true
        enableAlpn = true
      }
      hubble = {
        relay = {
          enabled = true
        }
        metrics = {
          enabled = [
            "dns:query;ignoreAAAA",
            "drop",
            "flow",
            "httpV2",
            "icmp",
            "port-distribution",
            "tcp",
          ]
          enableOpenMetrics = true
        }
      }
      prometheus = {
        enabled = true
      }
    }),
  ]

  depends_on = [
    kubectl_manifest.gateway_api_standard,
  ]
}

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }

  depends_on = [
    helm_release.cilium,
  ]
}

resource "kubernetes_config_map_v1" "argocd_cmp_ksops" {
  metadata {
    name      = "argocd-cmp-ksops"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  }

  data = {
    "plugin.yaml" = <<-YAML
      apiVersion: argoproj.io/v1alpha1
      kind: ConfigManagementPlugin
      metadata:
        name: ksops
      spec:
        allowConcurrency: false
        lockRepo: true
        discover:
          find:
            command:
              - sh
              - -c
              - test -f kustomization.yaml && test -f ../.sops.yaml
        generate:
          command:
            - sh
            - -c
            - kustomize build --enable-alpha-plugins --enable-exec .
    YAML
  }
}

resource "helm_release" "argocd" {
  name             = "argo-cd"
  namespace        = kubernetes_namespace_v1.argocd.metadata[0].name
  create_namespace = false
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version

  atomic  = true
  wait    = true
  timeout = 900

  values = [
    yamlencode({
      global = {
        domain = "argocd.${var.lab_base_domain}"
      }
      configs = {
        cm = {
          "application.resourceTrackingMethod" = "annotation"
          "oidc.config"                        = local.argocd_oidc_config
        }
        params = {
          "server.insecure" = true
        }
        rbac = {
          "policy.default" = "role:readonly"
          "policy.csv"     = "g, ArgoCD Admins, role:admin"
          scopes           = "[groups]"
        }
      }
      controller = {
        replicas = 2
        metrics = {
          enabled = true
        }
      }
      dex = {
        enabled = false
      }
      notifications = {
        enabled = true
      }
      repoServer = {
        replicas = 2
        metrics = {
          enabled = true
        }
        volumes = [
          {
            name = "argocd-cmp-ksops"
            configMap = {
              name = kubernetes_config_map_v1.argocd_cmp_ksops.metadata[0].name
            }
          },
          {
            name = "sops-age"
            secret = {
              secretName = "argocd-sops-age"
              optional   = true
            }
          },
          {
            name     = "cmp-tmp"
            emptyDir = {}
          },
        ]
        extraContainers = [
          {
            name    = "ksops"
            image   = "docker.io/viaductoss/ksops:v4.4.0@sha256:78add3d6191b4efce197a3a5ddcb70ea478270bbf4c18101263ea4a3d7e2d2f6"
            command = ["/var/run/argocd/argocd-cmp-server"]
            securityContext = {
              allowPrivilegeEscalation = false
              readOnlyRootFilesystem   = true
              runAsNonRoot             = true
              runAsUser                = 999
              capabilities = {
                drop = ["ALL"]
              }
            }
            volumeMounts = [
              {
                name      = "var-files"
                mountPath = "/var/run/argocd"
              },
              {
                name      = "plugins"
                mountPath = "/home/argocd/cmp-server/plugins"
              },
              {
                name      = "argocd-cmp-ksops"
                mountPath = "/home/argocd/cmp-server/config/plugin.yaml"
                subPath   = "plugin.yaml"
              },
              {
                name      = "sops-age"
                mountPath = "/home/argocd/.config/sops/age/keys.txt"
                subPath   = "keys.txt"
                readOnly  = true
              },
              {
                name      = "cmp-tmp"
                mountPath = "/tmp"
              },
            ]
          },
        ]
      }
      server = {
        replicas = 2
        ingress = {
          enabled = false
        }
        metrics = {
          enabled = true
        }
      }
      applicationSet = {
        replicas = 2
      }
      redis = {
        enabled = false
      }
      "redis-ha" = {
        enabled = true
      }
    }),
  ]

  depends_on = [
    kubernetes_config_map_v1.argocd_cmp_ksops,
  ]
}

resource "helm_release" "argocd_root_app" {
  name      = "argocd-root-app"
  namespace = "argocd"
  chart     = "${path.module}/charts/argocd-root-app"

  atomic  = true
  wait    = true
  timeout = 300

  values = [
    yamlencode({
      bootstrapRepoUrl      = var.bootstrap_repo_url
      bootstrapRevision     = var.bootstrap_revision
      appsRepoUrl           = var.apps_repo_url
      appsRevision          = var.apps_revision
      labBaseDomain         = var.lab_base_domain
      gatewayLoadBalancerIp = var.gateway_load_balancer_ip
      piholePrimaryIp       = var.pihole_primary_ip
      piholeSecondaryIp     = var.pihole_secondary_ip
      forgejoSshIp          = var.forgejo_ssh_ip
    }),
  ]

  depends_on = [
    helm_release.argocd,
  ]
}
