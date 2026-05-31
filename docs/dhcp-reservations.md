# DHCP Reservations

Create these DHCP reservations on the router or DHCP server for VLAN 80 before running `terraform apply`.

| VM | VMID | MAC address | Reserved IP | Role |
| --- | ---: | --- | --- | --- |
| `talos-cp-1` | 810 | `02:80:00:00:00:21` | `192.168.80.21` | Control plane |
| `talos-cp-2` | 811 | `02:80:00:00:00:22` | `192.168.80.22` | Control plane |
| `talos-cp-3` | 812 | `02:80:00:00:00:23` | `192.168.80.23` | Control plane |
| `talos-worker-1` | 813 | `02:80:00:00:00:24` | `192.168.80.24` | Worker, Longhorn storage |
| `talos-worker-2` | 814 | `02:80:00:00:00:25` | `192.168.80.25` | Worker, Longhorn storage |

Additional lab IPs:

| Purpose | IP or range |
| --- | --- |
| OPNsense Kubernetes gateway | `192.168.80.1` |
| Kubernetes API VIP | `192.168.80.10` |
| MetalLB pool | `192.168.80.30-192.168.80.49` |
| Default ingress IP | `192.168.80.30` |

The Proxmox VM NICs are tagged with VLAN ID `80`. Kea on OPNsense must serve VLAN 80 from `192.168.80.1:67`, and `vmbr0` must allow VLAN 80.
