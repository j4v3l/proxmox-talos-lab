variable "proxmox_endpoint" {
  description = "Proxmox API endpoint."
  type        = string
  default     = "https://192.168.0.119:8006/"
}

variable "proxmox_insecure" {
  description = "Allow insecure Proxmox TLS. Production must trust the Proxmox CA and leave this false."
  type        = bool
  default     = false
}

variable "proxmox_node_name" {
  description = "Proxmox node that will host the Talos VMs."
  type        = string
  default     = "pve"
}

variable "vm_datastore_id" {
  description = "Dedicated SSD/NVMe Proxmox datastore for all Talos VM disks."
  type        = string
  default     = "talos-ssd"
}

variable "iso_datastore_id" {
  description = "Proxmox datastore for the Talos ISO."
  type        = string
  default     = "local"
}

variable "secure_boot_enabled" {
  description = "Boot Talos with UEFI Secure Boot using Talos Secure Boot ISO and installer images."
  type        = bool
  default     = true
}

variable "efi_disk_datastore_id" {
  description = "Optional Proxmox datastore for the EFI vars disk. Leave empty to use vm_datastore_id."
  type        = string
  default     = ""
}

variable "secure_boot_pre_enrolled_keys" {
  description = "Use Proxmox EFI vars with distribution and Microsoft keys pre-enrolled. Leave false for the Talos default key enrollment flow."
  type        = bool
  default     = false
}

variable "siderolink_enabled" {
  description = "Enable the Talos-to-Omni SideroLink management overlay for every node."
  type        = bool
  default     = false
}

variable "siderolink_api_url" {
  description = "Full Omni SideroLink API URL, including the join token and any grpc_tunnel query parameter."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = trimspace(var.siderolink_api_url) == "" || can(regex("^https://[^[:space:]]+\\?.*jointoken=", trimspace(var.siderolink_api_url)))
    error_message = "siderolink_api_url must be empty or a full Omni SideroLink URL beginning with https:// and containing jointoken=."
  }
}

variable "network_bridge" {
  description = "Proxmox bridge used by the Talos VM NICs."
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag for the Talos VM NICs."
  type        = number
  default     = 80
}

variable "cluster_name" {
  description = "Talos/Kubernetes cluster name."
  type        = string
  default     = "talos-lab"
}

variable "lab_base_domain" {
  description = "LAN/VPN-only DNS suffix."
  type        = string
  default     = "lab.home.arpa"
}

variable "stopped_pbs_backups_verified" {
  description = "Explicit operator gate confirming stopped PBS backups of VMIDs 810-814 were completed and verified."
  type        = bool
  default     = false
}

variable "offline_recovery_capture_verified" {
  description = "Explicit operator gate confirming valuable data will be recovered only from offline clones."
  type        = bool
  default     = false
}

variable "hardware_capacity_verified" {
  description = "Explicit operator gate confirming at least 64 GiB RAM and a dedicated 1 TiB SSD/NVMe datastore are installed."
  type        = bool
  default     = false
}

variable "service_vm_gateway" {
  description = "Default gateway for cluster-independent service VMs on VLAN 80."
  type        = string
  default     = "192.168.80.1"
}

variable "service_vm_admin_user" {
  description = "Unprivileged administration account created by cloud-init."
  type        = string
  default     = "ops"
}

variable "service_vm_ssh_public_keys" {
  description = "SSH public keys authorized for the service VM administration account."
  type        = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHCsQ4NNDuuAj/NLrC9yXVoGRNU5DRTEqC2ybN+Y9Qjf j4v3l",
  ]

  validation {
    condition     = length(var.service_vm_ssh_public_keys) > 0 && alltrue([for key in var.service_vm_ssh_public_keys : startswith(key, "ssh-")])
    error_message = "At least one valid SSH public key is required for service VMs."
  }
}

variable "debian_cloud_image_url" {
  description = "Pinned Debian 13 generic cloud image used by the external Pi-hole and Forgejo runner VMs."
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/20260722-2547/debian-13-genericcloud-amd64-20260722-2547.qcow2"
}

variable "debian_cloud_image_sha512" {
  description = "SHA-512 checksum published by Debian for the pinned cloud image."
  type        = string
  default     = "735d1b2d0ef265a0c2323fdaa7d46e7bd7a1b984f73e8a785e638034bf07876e26374a9d809d713501270c071b3464d2ada0c5589f07742b95ed853cc6d48f45"
}

variable "service_vms" {
  description = "Cluster-independent production service VM inventory."
  type = map(object({
    hostname    = string
    vm_id       = number
    ip          = string
    mac_address = string
    cores       = number
    memory_mb   = number
    disk_gb     = number
    purpose     = string
  }))

  default = {
    pihole = {
      hostname    = "pihole-primary"
      vm_id       = 820
      ip          = "192.168.80.31"
      mac_address = "02:80:00:00:00:31"
      cores       = 1
      memory_mb   = 2048
      disk_gb     = 32
      purpose     = "Cluster-independent primary Pi-hole and Unbound"
    }
    forgejo_runner = {
      hostname    = "forgejo-runner"
      vm_id       = 821
      ip          = "192.168.80.34"
      mac_address = "02:80:00:00:00:34"
      cores       = 2
      memory_mb   = 4096
      disk_gb     = 64
      purpose     = "Repository-scoped rootless Podman Forgejo Actions runner"
    }
  }
}

variable "cluster_vip" {
  description = "Talos control-plane virtual IP used as the Kubernetes API endpoint."
  type        = string
  default     = "192.168.80.10"
}

variable "talos_version" {
  description = "Talos Linux version."
  type        = string
  default     = "v1.13.3"
}

variable "kubernetes_version" {
  description = "Kubernetes version installed by Talos."
  type        = string
  default     = "v1.35.5"
}

variable "install_disk" {
  description = "Disk path used by Talos for the OS installation."
  type        = string
  default     = "/dev/sda"
}

variable "output_dir" {
  description = "Directory where generated talosconfig and kubeconfig are written, relative to terraform/infra."
  type        = string
  default     = "../../_out"
}

variable "nodes" {
  description = "Talos VM inventory. IPs must match DHCP reservations on VLAN 80."
  type = map(object({
    hostname                   = string
    role                       = string
    vm_id                      = number
    ip                         = string
    mac_address                = string
    cores                      = number
    memory_mb                  = number
    os_disk_datastore_id       = optional(string)
    os_disk_gb                 = number
    longhorn_disk_datastore_id = optional(string)
    longhorn_disk_gb           = number
    longhorn_disk_name         = string
    longhorn_serial            = string
  }))

  default = {
    cp1 = {
      hostname                   = "talos-cp-1"
      role                       = "controlplane"
      vm_id                      = 810
      ip                         = "192.168.80.21"
      mac_address                = "02:80:00:00:00:21"
      cores                      = 2
      memory_mb                  = 4096
      os_disk_datastore_id       = null
      os_disk_gb                 = 40
      longhorn_disk_datastore_id = null
      longhorn_disk_gb           = 0
      longhorn_disk_name         = ""
      longhorn_serial            = ""
    }
    cp2 = {
      hostname                   = "talos-cp-2"
      role                       = "controlplane"
      vm_id                      = 811
      ip                         = "192.168.80.22"
      mac_address                = "02:80:00:00:00:22"
      cores                      = 2
      memory_mb                  = 4096
      os_disk_datastore_id       = null
      os_disk_gb                 = 40
      longhorn_disk_datastore_id = null
      longhorn_disk_gb           = 0
      longhorn_disk_name         = ""
      longhorn_serial            = ""
    }
    cp3 = {
      hostname                   = "talos-cp-3"
      role                       = "controlplane"
      vm_id                      = 812
      ip                         = "192.168.80.23"
      mac_address                = "02:80:00:00:00:23"
      cores                      = 2
      memory_mb                  = 4096
      os_disk_datastore_id       = null
      os_disk_gb                 = 40
      longhorn_disk_datastore_id = null
      longhorn_disk_gb           = 0
      longhorn_disk_name         = ""
      longhorn_serial            = ""
    }
    worker1 = {
      hostname                   = "talos-worker-1"
      role                       = "worker"
      vm_id                      = 813
      ip                         = "192.168.80.24"
      mac_address                = "02:80:00:00:00:24"
      cores                      = 4
      memory_mb                  = 10240
      os_disk_datastore_id       = null
      os_disk_gb                 = 40
      longhorn_disk_datastore_id = null
      longhorn_disk_gb           = 250
      longhorn_disk_name         = "longhorn"
      longhorn_serial            = "lh-813"
    }
    worker2 = {
      hostname                   = "talos-worker-2"
      role                       = "worker"
      vm_id                      = 814
      ip                         = "192.168.80.25"
      mac_address                = "02:80:00:00:00:25"
      cores                      = 4
      memory_mb                  = 10240
      os_disk_datastore_id       = null
      os_disk_gb                 = 40
      longhorn_disk_datastore_id = null
      longhorn_disk_gb           = 250
      longhorn_disk_name         = "longhorn"
      longhorn_serial            = "lh-814"
    }
  }

  validation {
    condition     = alltrue([for node in var.nodes : contains(["controlplane", "worker"], node.role)])
    error_message = "Each node role must be controlplane or worker."
  }

  validation {
    condition = alltrue([
      for node in values(var.nodes) :
      node.os_disk_gb >= 30 &&
      (node.role != "worker" || (node.memory_mb >= 10240 && node.longhorn_disk_gb >= 250))
    ])
    error_message = "Production nodes require at least 30 GiB OS disks; workers require at least 10 GiB RAM and 250 GiB Longhorn disks."
  }
}
