locals {
  efi_disk_datastore_id = var.efi_disk_datastore_id != "" ? var.efi_disk_datastore_id : var.vm_datastore_id
  siderolink_api_url    = trimspace(var.siderolink_api_url)
  siderolink_configured = var.siderolink_enabled && local.siderolink_api_url != ""

  controlplane_nodes = {
    for key, node in var.nodes : key => node
    if node.role == "controlplane"
  }

  worker_nodes = {
    for key, node in var.nodes : key => node
    if node.role == "worker"
  }

  planned_node_ips = [
    for key in sort(keys(var.nodes)) : var.nodes[key].ip
  ]

  planned_controlplane_ips = [
    for key in sort(keys(local.controlplane_nodes)) : local.controlplane_nodes[key].ip
  ]

  node_ips = local.planned_node_ips

  controlplane_ips = local.planned_controlplane_ips

  bootstrap_node_ip = local.planned_controlplane_ips[0]

  talos_iso_url         = var.secure_boot_enabled ? data.talos_image_factory_urls.this.urls.iso_secureboot : data.talos_image_factory_urls.this.urls.iso
  talos_installer_image = var.secure_boot_enabled ? data.talos_image_factory_urls.this.urls.installer_secureboot : data.talos_image_factory_urls.this.urls.installer
  siderolink_config_patches = local.siderolink_configured ? [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "SideroLinkConfig"
      apiUrl     = local.siderolink_api_url
    }),
  ] : []

  talos_common_config_patch = yamlencode({
    machine = {
      install = {
        disk  = var.install_disk
        image = local.talos_installer_image
      }
      features = {
        kubePrism = {
          enabled = true
          port    = 7445
        }
      }
    }
    cluster = {
      network = {
        cni = {
          name = "none"
        }
      }
      proxy = {
        disabled = true
      }
    }
  })
}
