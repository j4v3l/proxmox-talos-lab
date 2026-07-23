# Proxmox + Talos Production Homelab

Production-hardened, LAN/VPN-only Talos Kubernetes on one Proxmox host, with a hybrid GitHub/Forgejo GitOps control plane.

This repository is the public off-cluster bootstrap and disaster-recovery source for `j4v3l/proxmox-talos-lab`. The private `j4v3l/talos-apps` repository contains application values and SOPS-encrypted secrets; Forgejo is authoritative and GitHub is its one-way off-site mirror.

## Current deployment status

The repository configuration is prepared for a clean rebuild, but the live host is not production-ready and must not be rebuilt yet:

- Install at least 64 GiB RAM.
- Add a dedicated 1 TiB-or-larger SSD/NVMe datastore named in local Terraform inputs.
- Verify stopped PBS backups and offline recovery clones.
- Supply independent encrypted/versioned S3-compatible backup buckets.
- Trust the Proxmox CA; production Terraform refuses `proxmox_insecure=true`.

Terraform enforces the backup, recovery, capacity, and TLS acknowledgements before it can replace or create VMs. The existing live cluster is intentionally left untouched until those gates are true.

## Final topology

| Endpoint | Purpose |
| --- | --- |
| `192.168.80.10` | Kubernetes API VIP |
| `192.168.80.21-23` | Talos control planes |
| `192.168.80.24-25` | Talos workers |
| `192.168.80.30` | Cilium HTTPS Gateway |
| `192.168.80.31` | External primary Pi-hole/Unbound VM |
| `192.168.80.32` | Kubernetes secondary Pi-hole/Unbound |
| `192.168.80.33:22` | Forgejo SSH LoadBalancer |
| `192.168.80.34` | Dedicated rootless Podman runner VM |

The two workers have 10 GiB RAM, 40 GiB OS disks, and dedicated 250 GiB Longhorn disks. `longhorn-2r` uses two replicas, best-effort locality, `Retain`, recurring snapshots, and off-host backups.

## Ownership boundary

- `terraform/infra`: Proxmox VMs, Talos machine secrets/configuration, external Pi-hole VM, and runner VM.
- `terraform/platform`: Gateway API v1.4.1 CRDs, Cilium 1.19.6 with kube-proxy replacement, Argo CD, KSOPS, and the root Application.
- `gitops/clusters/talos-lab`: public bootstrap Applications and exact `bootstrap`, `platform`, and `apps` AppProjects.
- Private `talos-apps`: pinned platform values, CloudNativePG, Authentik, Forgejo, Pi-hole, policy, monitoring, and encrypted secrets.
- OPNsense: DHCP, forced DNS, DoT blocking, inter-VLAN policy, and official `os-crowdsec`.

All ingress-nginx and Kubernetes CrowdSec bouncer configuration has been removed. HTTP services use Gateway API `HTTPRoute`; Forgejo SSH has its own LoadBalancer.

## Safe bootstrap

```bash
cp terraform/backend.s3.hcl.example terraform/backend.s3.hcl
cp terraform/infra/terraform.tfvars.example terraform/infra/production.auto.tfvars
cp terraform/platform/terraform.tfvars.example terraform/platform/production.auto.tfvars
cp ansible/inventory/hosts.ini.example ansible/inventory/hosts.ini

just preflight
just ci
just init-backends
```

Only after the hardware, backup, and recovery gates are verified:

```bash
terraform -chdir=terraform/infra plan
terraform -chdir=terraform/infra apply
just configure-pihole
just configure-forgejo-runner
terraform -chdir=terraform/platform plan
terraform -chdir=terraform/platform apply
just bootstrap-sops-age
```

CI never runs `terraform apply` or `kubectl`. Protected merges to `main` are deployment events; Argo CD performs delivery.

See [production readiness](docs/production-readiness.md), [hybrid GitOps](docs/app-layer.md), [operations](docs/operations.md), [backup and restore](docs/backups-and-restore.md), and [incident response](docs/incident-response.md).
