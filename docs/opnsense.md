# OPNsense VLAN 80 Guide

This project validates that OPNsense is reachable, but it does not change firewall, DHCP, NAT, or IDS settings. Apply these items manually in OPNsense or through a separate router-management workflow.

## Required Interface and DHCP State

- Kubernetes VLAN interface: `192.168.80.1/24`
- Kea DHCP listener: `192.168.80.1:67`
- VLAN 80 DHCP range: `192.168.80.0/24`
- Talos DHCP reservations:
  - `02:80:00:00:00:21` -> `192.168.80.21`
  - `02:80:00:00:00:22` -> `192.168.80.22`
  - `02:80:00:00:00:23` -> `192.168.80.23`
  - `02:80:00:00:00:24` -> `192.168.80.24`
  - `02:80:00:00:00:25` -> `192.168.80.25`

Reserve these service IPs outside the DHCP dynamic pool:

- Kubernetes API VIP: `192.168.80.10`
- Ingress VIP: `192.168.80.30`
- MetalLB pool: `192.168.80.30-192.168.80.49`

## Firewall Policy

Required allow rules:

- Admin and WireGuard networks can reach `192.168.80.10:6443`.
- Admin and WireGuard networks can reach Talos node IPs `192.168.80.21-25` on TCP `50000`.
- Caddy host `192.168.10.128` can reach `192.168.80.30` on TCP `80` and `443`.
- VLAN 80 can use outbound NAT for internet access.

Required deny/default behavior:

- VLAN 80 cannot reach unrelated RFC1918 networks unless an explicit allow rule exists.

## IDS

- IDS status remains healthy after VLAN 80 changes.
- `HOME_NET` includes `192.168.80.0/24`.

## Cleanup

- Remove old Talos DHCP reservations for `192.168.0.21-192.168.0.34`.
- Clear stale active Talos LAN leases from the old LAN scope.
- Confirm no old Talos reservations remain on the LAN interface.

## Manual Validation

From this workstation:

```bash
just opnsense-check
```

From a VLAN 80 test client:

```bash
ip addr
ip route
curl -I --connect-timeout 5 https://opnsense.org
```

From the Caddy host at `192.168.10.128`, after the cluster is running:

```bash
curl -I --connect-timeout 5 http://192.168.80.30
curl -kI --connect-timeout 5 https://192.168.80.30
```

Switch validation remains manual: trunk port 3 must tag VLAN 80.

