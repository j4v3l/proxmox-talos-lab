# OPNsense production policy

OPNsense owns VLAN 80 routing, Kea DHCP, DNS enforcement, and perimeter remediation.

Required configuration:

- Interface `192.168.80.1/24`; DHCP reservations from [dhcp-reservations.md](dhcp-reservations.md).
- Advertise DNS servers `192.168.80.31` and `192.168.80.32`.
- Redirect unauthorized VLAN/LAN TCP and UDP port 53 to the two Pi-holes.
- Block outbound TCP and UDP 853 except explicitly approved resolvers.
- Permit admin/VPN networks to `.10:6443`, `.21-.25:50000`, `.30:443`, `.31-.32:53`, and `.33:22`.
- Permit the runner VM only to Forgejo HTTPS, public package/chart registries, and normal DNS/NTP. Deny access to Kubernetes, Talos, Proxmox, and backup networks.
- Default-deny VLAN 80 access to unrelated RFC1918 networks.
- Install the official `os-crowdsec` plugin and keep its firewall aliases/tables healthy.

Pi-hole DHCP remains disabled. Do not configure a Kubernetes ingress bouncer.
