variable "proxmox_endpoint" {
  description = "Proxmox API endpoint."
  type        = string
  default     = "https://192.168.0.119:8006/"
}

variable "proxmox_insecure" {
  description = "Allow the Proxmox provider to use the self-signed Proxmox TLS certificate."
  type        = bool
  default     = true
}

variable "proxmox_node_name" {
  description = "Proxmox node that will host the Talos VMs."
  type        = string
  default     = "pve"
}

variable "vm_datastore_id" {
  description = "Proxmox datastore for VM disks."
  type        = string
  default     = "local-lvm"
}

variable "iso_datastore_id" {
  description = "Proxmox datastore for the Talos ISO."
  type        = string
  default     = "local"
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
    hostname           = string
    role               = string
    vm_id              = number
    ip                 = string
    mac_address        = string
    cores              = number
    memory_mb          = number
    os_disk_gb         = number
    longhorn_disk_gb   = number
    longhorn_disk_name = string
    longhorn_serial    = string
  }))

  default = {
    cp1 = {
      hostname           = "talos-cp-1"
      role               = "controlplane"
      vm_id              = 810
      ip                 = "192.168.80.21"
      mac_address        = "02:80:00:00:00:21"
      cores              = 2
      memory_mb          = 4096
      os_disk_gb         = 32
      longhorn_disk_gb   = 0
      longhorn_disk_name = ""
      longhorn_serial    = ""
    }
    cp2 = {
      hostname           = "talos-cp-2"
      role               = "controlplane"
      vm_id              = 811
      ip                 = "192.168.80.22"
      mac_address        = "02:80:00:00:00:22"
      cores              = 2
      memory_mb          = 4096
      os_disk_gb         = 32
      longhorn_disk_gb   = 0
      longhorn_disk_name = ""
      longhorn_serial    = ""
    }
    cp3 = {
      hostname           = "talos-cp-3"
      role               = "controlplane"
      vm_id              = 812
      ip                 = "192.168.80.23"
      mac_address        = "02:80:00:00:00:23"
      cores              = 2
      memory_mb          = 4096
      os_disk_gb         = 32
      longhorn_disk_gb   = 0
      longhorn_disk_name = ""
      longhorn_serial    = ""
    }
    worker1 = {
      hostname           = "talos-worker-1"
      role               = "worker"
      vm_id              = 813
      ip                 = "192.168.80.24"
      mac_address        = "02:80:00:00:00:24"
      cores              = 4
      memory_mb          = 8192
      os_disk_gb         = 32
      longhorn_disk_gb   = 100
      longhorn_disk_name = "longhorn"
      longhorn_serial    = "lh-813"
    }
    worker2 = {
      hostname           = "talos-worker-2"
      role               = "worker"
      vm_id              = 814
      ip                 = "192.168.80.25"
      mac_address        = "02:80:00:00:00:25"
      cores              = 4
      memory_mb          = 8192
      os_disk_gb         = 32
      longhorn_disk_gb   = 100
      longhorn_disk_name = "longhorn"
      longhorn_serial    = "lh-814"
    }
  }

  validation {
    condition     = alltrue([for node in var.nodes : contains(["controlplane", "worker"], node.role)])
    error_message = "Each node role must be controlplane or worker."
  }
}
