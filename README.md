# Proxmox + Talos Beginner Lab

This repository bootstraps a five-node Talos Kubernetes lab on a single Proxmox host, installs the base platform with Terraform, and uses Argo CD for the learning app layer.

The lab targets your Proxmox server at `192.168.0.119` and a VLAN 80 Kubernetes network at `192.168.80.0/24`.

## What This Builds

- 3 Talos control-plane VMs: `talos-cp-1` through `talos-cp-3`
- 2 Talos worker VMs: `talos-worker-1` and `talos-worker-2`
- OPNsense Kubernetes gateway: `192.168.80.1`
- Kubernetes API VIP: `192.168.80.10`
- Node DHCP reservations: `192.168.80.21-25`
- MetalLB pool: `192.168.80.30-49`
- Ingress IP: `192.168.80.30`
- AdGuard DNS IP: `192.168.80.31`
- Bootstrap UI hostnames through `sslip.io`, for example `rancher.192.168.80.30.sslip.io`
- Daily-use UI hostnames through AdGuard local DNS, for example `rancher.lab.home.arpa`

## Platform Split

- `terraform/infra` creates the Proxmox VMs and bootstraps Talos.
- `terraform/platform` installs the base cluster services: Cilium, MetalLB, ingress-nginx, cert-manager, Rancher, Argo CD, and metrics-server.
- `gitops/clusters/talos-lab` is the Argo CD app-of-apps overlay for the learning app layer.
- `gitops/apps` contains local charts for small lab services and helper resources.

## App Layer

When `gitops_repo_url` is set and the root Argo app is enabled, Argo CD manages:

- Longhorn plus a single-replica lab StorageClass
- Homarr
- Uptime Kuma
- Forgejo
- Forgejo runner bootstrap app
- Prometheus + Grafana
- Loki + Grafana Alloy
- AdGuard Home
- whoami

The current smoke path still works with `gitops_repo_url = ""`. In that mode, Terraform installs only Longhorn and `whoami` directly.

Run the preflight checks before applying Terraform:

```bash
just preflight
```

The same checks are also available through `just preflight`, `just validate`, and `just render-checks`.

## Quick Start

1. Create DHCP reservations from [docs/dhcp-reservations.md](docs/dhcp-reservations.md).
2. Confirm VLAN 80 is allowed end-to-end on OPNsense, switch trunk port 3, Proxmox `vmbr0`, and the VM port path.
3. Review the OPNsense policy guide in [docs/opnsense.md](docs/opnsense.md).
4. For the first smaller validation run, follow [docs/smoke-run.md](docs/smoke-run.md).
5. Export Proxmox API credentials. The bpg provider supports environment variables such as:

```bash
export PROXMOX_VE_USERNAME='root@pam'
export PROXMOX_VE_PASSWORD='your-password'
```

Or use an API token:

```bash
export PROXMOX_VE_API_TOKEN='root@pam!token-name=token-value'
```

6. Copy example variables and edit only the values you understand:

```bash
cp terraform/infra/terraform.tfvars.example terraform/infra/lab.auto.tfvars
cp terraform/platform/terraform.tfvars.example terraform/platform/lab.auto.tfvars
```

7. Push this repository to GitHub and set `gitops_repo_url = "https://github.com/j4v3l/proxmox-talos-lab.git"` plus `gitops_revision = "dev"` in `terraform/platform/lab.auto.tfvars`. Argo CD uses that URL as the source of truth for the app layer.

8. Run preflight:

```bash
just preflight
```

9. Create the VMs and bootstrap Talos:

```bash
cd terraform/infra
terraform init
terraform plan
terraform apply
```

10. Install platform services:

```bash
cd ../platform
terraform init
terraform plan
terraform apply
```

11. Point `kubectl` and `talosctl` at the generated configs:

```bash
export KUBECONFIG="$(pwd)/../../_out/kubeconfig"
export TALOSCONFIG="$(pwd)/../../_out/talosconfig"
```

12. Follow the GitOps app-layer guide in [docs/app-layer.md](docs/app-layer.md) for the first Argo sync, AdGuard rewrites, and Forgejo runner bootstrap.

## Beginner Notes

- Terraform stage 1, `terraform/infra`, owns only the Proxmox VMs and Talos cluster bootstrap.
- Terraform stage 2, `terraform/platform`, owns only the base add-ons needed before GitOps is useful.
- Argo CD then owns the learning app layer from `gitops/clusters/talos-lab`.
- Secrets and generated kubeconfigs are written under `_out/` and ignored by Git.
- Do not commit `.tfstate`, `.tfvars`, kubeconfigs, Talos configs, passwords, or API tokens.
