# Smoke Run

The smoke profile is for proving the stack on the current Proxmox host before final RAM and storage sizing is fixed.

The smoke profile also inherits the repo Secure Boot default. If the current Talos VMs were created before Secure Boot was enabled in the repo, rebuild them during the infra apply so they reinstall from the Secure Boot ISO and installer image.

Smoke VM sizes:

| Role | Count | CPU | RAM | OS disk | Longhorn disk |
| --- | ---: | ---: | ---: | ---: | ---: |
| Control plane | 3 | 2 cores | 3 GiB | 20 GiB | none |
| Worker | 2 | 4 cores | 6 GiB | 20 GiB | 30 GiB |

The smoke files are intentionally ignored by Git:

- `terraform/infra/smoke.auto.tfvars`
- `terraform/platform/smoke.auto.tfvars`
- `_out/proxmox.env`

Current OPNsense dynamic leases discovered during the smoke run:

| VM | MAC address | Smoke IP |
| --- | --- | --- |
| `talos-cp-1` | `02:80:00:00:00:21` | `192.168.80.106` |
| `talos-cp-2` | `02:80:00:00:00:22` | `192.168.80.107` |
| `talos-cp-3` | `02:80:00:00:00:23` | `192.168.80.108` |
| `talos-worker-1` | `02:80:00:00:00:24` | `192.168.80.110` |
| `talos-worker-2` | `02:80:00:00:00:25` | `192.168.80.109` |

The final intended reservations remain `192.168.80.21-25`; this smoke mapping should be removed once those OPNsense reservations are fixed. The current smoke tfvars in `terraform/infra/smoke.auto.tfvars` must match the temporary leases that OPNsense is actually handing out during the smoke run.

Run order:

```bash
just proxmox-token
source _out/proxmox.env
just preflight-smoke
just init
terraform -chdir=terraform/infra apply
export KUBECONFIG="$PWD/_out/kubeconfig"
export TALOSCONFIG="$PWD/_out/talosconfig"
just verify-secureboot
# optional when using Omni SaaS SideroLink
just verify-siderolink
terraform -chdir=terraform/platform apply
just post-bootstrap-smoke-check
just ingress-smoke-check
```

For a live cluster created by an older non-Secure-Boot revision of this repo, rebuild the Talos infra during the apply so the VMs reinstall from the Secure Boot assets and Talos bootstraps again:

```bash
just infra-secureboot-rebuild
```

Use these Talos checks with the current dynamic smoke leases:

```bash
talosctl get members --nodes 192.168.80.106 --endpoints 192.168.80.106
talosctl etcd members --nodes 192.168.80.106 --endpoints 192.168.80.106
for ip in 192.168.80.106 192.168.80.107 192.168.80.108 192.168.80.110 192.168.80.109; do
  talosctl services --nodes "$ip" --endpoints 192.168.80.106 | awk 'NR==1 || /apid|etcd|kubelet|cri|containerd/'
done
```

If local DNS does not resolve `sslip.io`, `just ingress-smoke-check` pins each hostname to `192.168.80.30` during the check.

If you want Talos to register to Omni over SideroLink during the smoke run, add these ignored local values to `terraform/infra/smoke.auto.tfvars` before the infra apply:

```hcl
siderolink_enabled = true
siderolink_api_url = "https://<your-omni-siderolink-endpoint>/?jointoken=<token>&grpc_tunnel=true"
```

SideroLink is a Talos-to-Omni management overlay only. It does not replace the current smoke LAN node IPs, the API VIP, ingress VIP, or the Cilium data plane.

To return to full sizing later, remove the smoke tfvars files and update capacity before applying again.
