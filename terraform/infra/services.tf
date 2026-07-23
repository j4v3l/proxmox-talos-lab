resource "proxmox_download_file" "debian_cloud" {
  content_type       = "import"
  datastore_id       = var.iso_datastore_id
  node_name          = var.proxmox_node_name
  url                = var.debian_cloud_image_url
  file_name          = "debian-13-genericcloud-amd64-20260722-2547.qcow2"
  checksum           = var.debian_cloud_image_sha512
  checksum_algorithm = "sha512"
}

resource "proxmox_virtual_environment_vm" "service" {
  for_each = var.service_vms

  name        = each.value.hostname
  description = "${each.value.purpose}; managed by Terraform and configured by Ansible."
  tags        = ["homelab", "production", "service", "terraform"]

  node_name       = var.proxmox_node_name
  vm_id           = each.value.vm_id
  bios            = "ovmf"
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"
  started         = true
  on_boot         = true
  stop_on_destroy = true
  protection      = true
  boot_order      = ["scsi0"]

  agent {
    enabled = false
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory_mb
  }

  efi_disk {
    datastore_id      = local.efi_disk_datastore_id
    pre_enrolled_keys = true
    type              = "4m"
  }

  operating_system {
    type = "l26"
  }

  network_device {
    bridge      = var.network_bridge
    firewall    = false
    mac_address = each.value.mac_address
    model       = "virtio"
    queues      = 2
    vlan_id     = var.vlan_id
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    import_from  = proxmox_download_file.debian_cloud.id
    size         = each.value.disk_gb
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  initialization {
    datastore_id = var.vm_datastore_id

    dns {
      domain  = var.lab_base_domain
      servers = [var.service_vm_gateway]
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.service_vm_gateway
      }
    }

    user_account {
      keys     = var.service_vm_ssh_public_keys
      username = var.service_vm_admin_user
    }
  }

  startup {
    order      = each.key == "pihole" ? 1 : 2
    up_delay   = 30
    down_delay = 30
  }

  depends_on = [
    terraform_data.rebuild_safety_gate,
  ]
}
