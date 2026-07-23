# VLAN 80 addressing

OPNsense/Kea remains DHCP authority. Talos uses DHCP with fixed reservations; the two Debian service VMs use cloud-init static addresses.

| Host | VMID | MAC | Address | Role |
| --- | ---: | --- | --- | --- |
| `talos-cp-1` | 810 | `02:80:00:00:00:21` | `192.168.80.21` | Control plane |
| `talos-cp-2` | 811 | `02:80:00:00:00:22` | `192.168.80.22` | Control plane |
| `talos-cp-3` | 812 | `02:80:00:00:00:23` | `192.168.80.23` | Control plane |
| `talos-worker-1` | 813 | `02:80:00:00:00:24` | `192.168.80.24` | Worker/storage |
| `talos-worker-2` | 814 | `02:80:00:00:00:25` | `192.168.80.25` | Worker/storage |
| `pihole-primary` | 820 | `02:80:00:00:00:31` | `192.168.80.31` | External DNS |
| `forgejo-runner` | 821 | `02:80:00:00:00:34` | `192.168.80.34` | CI runner |

Reserved service addresses:

- API VIP: `.10`
- Cilium Gateway: `.30`
- Pi-hole primary/secondary: `.31` and `.32`
- Forgejo SSH: `.33`
- MetalLB pool: `.30/32` and `.32-.49`; `.31` is explicitly excluded.
