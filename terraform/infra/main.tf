provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure
}

resource "terraform_data" "rebuild_safety_gate" {
  input = {
    stopped_pbs_backups_verified      = var.stopped_pbs_backups_verified
    offline_recovery_capture_verified = var.offline_recovery_capture_verified
    hardware_capacity_verified        = var.hardware_capacity_verified
    production_tls_verified           = !var.proxmox_insecure
  }

  lifecycle {
    precondition {
      condition = (
        var.stopped_pbs_backups_verified &&
        var.offline_recovery_capture_verified &&
        var.hardware_capacity_verified &&
        !var.proxmox_insecure
      )
      error_message = "Rebuild blocked: verify stopped PBS backups, offline recovery capture, 64 GiB+/1 TiB+ SSD capacity, and trusted Proxmox TLS first."
    }
  }
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          "siderolabs/iscsi-tools",
          "siderolabs/qemu-guest-agent",
          "siderolabs/util-linux-tools",
        ]
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "metal"
  architecture  = "amd64"
}

resource "proxmox_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.iso_datastore_id
  node_name    = var.proxmox_node_name
  url          = local.talos_iso_url
  file_name    = "talos-${var.talos_version}-${talos_image_factory_schematic.this.id}-metal-amd64${var.secure_boot_enabled ? "-secureboot" : ""}.iso"
}

resource "terraform_data" "talos_boot_mode" {
  input = {
    secure_boot_enabled           = var.secure_boot_enabled
    secure_boot_pre_enrolled_keys = var.secure_boot_pre_enrolled_keys
  }
}

resource "proxmox_virtual_environment_vm" "talos" {
  for_each = var.nodes

  name        = each.value.hostname
  description = "Talos ${each.value.role} node for ${var.cluster_name}; managed by Terraform."
  tags        = ["homelab", "talos", "terraform"]

  node_name       = var.proxmox_node_name
  vm_id           = each.value.vm_id
  bios            = var.secure_boot_enabled ? "ovmf" : "seabios"
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-pci"
  started         = true
  on_boot         = true
  stop_on_destroy = true
  boot_order      = ["scsi0", "ide2"]

  agent {
    enabled = true
    timeout = "20m"
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory_mb
  }

  dynamic "efi_disk" {
    for_each = var.secure_boot_enabled ? [1] : []

    content {
      datastore_id      = local.efi_disk_datastore_id
      pre_enrolled_keys = var.secure_boot_pre_enrolled_keys
      type              = "4m"
    }
  }

  operating_system {
    type = "l26"
  }

  network_device {
    bridge      = var.network_bridge
    firewall    = false
    mac_address = each.value.mac_address
    model       = "virtio"
    vlan_id     = var.vlan_id
  }

  disk {
    datastore_id = coalesce(each.value.os_disk_datastore_id, var.vm_datastore_id)
    interface    = "scsi0"
    size         = each.value.os_disk_gb
  }

  dynamic "disk" {
    for_each = each.value.longhorn_disk_gb > 0 ? [each.value] : []

    content {
      datastore_id = coalesce(disk.value.longhorn_disk_datastore_id, var.vm_datastore_id)
      interface    = "scsi1"
      serial       = disk.value.longhorn_serial
      size         = disk.value.longhorn_disk_gb
    }
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide2"
  }

  serial_device {}

  lifecycle {
    replace_triggered_by = [
      terraform_data.talos_boot_mode,
    ]
  }

  depends_on = [
    terraform_data.rebuild_safety_gate,
  ]
}

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${var.cluster_vip}:6443"
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches = concat([
    local.talos_common_config_patch,
  ], local.siderolink_config_patches)
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${var.cluster_vip}:6443"
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches = concat([
    local.talos_common_config_patch,
  ], local.siderolink_config_patches)
}

resource "talos_machine_configuration_apply" "controlplane" {
  for_each = local.controlplane_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  endpoint                    = each.value.ip
  node                        = each.value.ip

  config_patches = [
    yamlencode({
      machine = {
        network = {
          interfaces = [
            {
              deviceSelector = {
                physical = true
              }
              dhcp = true
              vip = {
                ip = var.cluster_vip
              }
            }
          ]
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      hostname   = each.value.hostname
      auto       = "off"
    }),
  ]

  depends_on = [
    proxmox_virtual_environment_vm.talos,
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = local.worker_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  endpoint                    = each.value.ip
  node                        = each.value.ip

  config_patches = [
    yamlencode({
      machine = {
        network = {
          interfaces = [
            {
              deviceSelector = {
                physical = true
              }
              dhcp = true
            }
          ]
        }
        nodeLabels = {
          "longhorn.io/storage" = "true"
        }
        kubelet = {
          extraMounts = [
            {
              destination = "/var/mnt/longhorn"
              options     = ["bind", "rshared", "rw"]
              source      = "/var/mnt/longhorn"
              type        = "bind"
            }
          ]
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      hostname   = each.value.hostname
      auto       = "off"
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = each.value.longhorn_disk_name
      provisioning = {
        diskSelector = {
          match = format("'%s' in disk.symlinks", format("/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_%s", each.value.longhorn_serial))
        }
        maxSize = format("%dGB", each.value.longhorn_disk_gb)
        minSize = format("%dGB", max(each.value.longhorn_disk_gb - 10, 1))
      }
    }),
  ]

  depends_on = [
    proxmox_virtual_environment_vm.talos,
  ]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoint             = local.bootstrap_node_ip
  node                 = local.bootstrap_node_ip

  depends_on = [
    talos_machine_configuration_apply.controlplane,
  ]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoint             = local.bootstrap_node_ip
  node                 = local.bootstrap_node_ip

  depends_on = [
    talos_machine_bootstrap.this,
    talos_machine_configuration_apply.worker,
  ]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.controlplane_ips
  nodes                = local.node_ips
}

resource "local_sensitive_file" "talosconfig" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = "${path.module}/${var.output_dir}/talosconfig"
  file_permission = "0600"
}

resource "local_sensitive_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${path.module}/${var.output_dir}/kubeconfig"
  file_permission = "0600"
}
