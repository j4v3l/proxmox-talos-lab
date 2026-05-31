# Proxmox + Talos Beginner Lab

This repository bootstraps a five-node Talos Kubernetes lab on a single Proxmox host, then installs the platform pieces needed for learning: Cilium, MetalLB, ingress-nginx, cert-manager, Rancher, Argo CD, Longhorn, and a small sample workload.

The lab targets your Proxmox server at `192.168.0.119` and a VLAN 80 Kubernetes network at `192.168.80.0/24`.

## What This Builds

- 3 Talos control-plane VMs: `talos-cp-1` through `talos-cp-3`
- 2 Talos worker VMs: `talos-worker-1` and `talos-worker-2`
- OPNsense Kubernetes gateway: `192.168.80.1`
- Kubernetes API VIP: `192.168.80.10`
- Node DHCP reservations: `192.168.80.21-25`
- MetalLB pool: `192.168.80.30-49`
- Ingress IP: `192.168.80.30`
- UI hostnames through `sslip.io`, for example `rancher.192.168.80.30.sslip.io`

## Important Capacity Gate

The current Proxmox host is too full for this lab as inspected on May 31, 2026:

- `local-lvm` had about 36 GiB free.
- Available RAM was about 10 GiB.
- The planned VMs reserve about 360 GiB of VM disk and 28 GiB RAM.

Run the preflight checks before applying Terraform:

```bash
just preflight
```

It is expected to fail until storage, RAM, VLAN 80, OPNsense, and DHCP reservations are ready.

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

7. Run preflight:

```bash
just preflight
```

8. Create the VMs and bootstrap Talos:

```bash
cd terraform/infra
terraform init
terraform plan
terraform apply
```

9. Install platform services:

```bash
cd ../platform
terraform init
terraform plan
terraform apply
```

10. Point `kubectl` and `talosctl` at the generated configs:

```bash
export KUBECONFIG="$(pwd)/../../_out/kubeconfig"
export TALOSCONFIG="$(pwd)/../../_out/talosconfig"
```

## Beginner Notes

- Terraform stage 1, `terraform/infra`, owns only the Proxmox VMs and Talos cluster bootstrap.
- Terraform stage 2, `terraform/platform`, owns core cluster add-ons that need to exist before GitOps is useful.
- Argo CD then owns the app layer from `gitops/clusters/talos-lab`.
- Secrets and generated kubeconfigs are written under `_out/` and ignored by Git.
- Do not commit `.tfstate`, `.tfvars`, kubeconfigs, Talos configs, passwords, or API tokens.
