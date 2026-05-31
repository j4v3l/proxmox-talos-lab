# Smoke Run

The smoke profile is for proving the stack on the current Proxmox host before final RAM and storage sizing is fixed.

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
| `talos-cp-1` | `02:80:00:00:00:21` | `192.168.80.103` |
| `talos-cp-2` | `02:80:00:00:00:22` | `192.168.80.102` |
| `talos-cp-3` | `02:80:00:00:00:23` | `192.168.80.101` |
| `talos-worker-1` | `02:80:00:00:00:24` | `192.168.80.105` |
| `talos-worker-2` | `02:80:00:00:00:25` | `192.168.80.104` |

The final intended reservations remain `192.168.80.21-25`; this smoke mapping should be removed once those OPNsense reservations are fixed.

Run order:

```bash
just proxmox-token
source _out/proxmox.env
just preflight-smoke
just init
terraform -chdir=terraform/infra apply
export KUBECONFIG="$PWD/_out/kubeconfig"
export TALOSCONFIG="$PWD/_out/talosconfig"
terraform -chdir=terraform/platform apply
just post-bootstrap-smoke-check
just ingress-smoke-check
```

Use these Talos checks with the current dynamic smoke leases:

```bash
talosctl get members --nodes 192.168.80.103 --endpoints 192.168.80.103
talosctl etcd members --nodes 192.168.80.103 --endpoints 192.168.80.103
for ip in 192.168.80.103 192.168.80.102 192.168.80.101 192.168.80.105 192.168.80.104; do
  talosctl services --nodes "$ip" --endpoints 192.168.80.103 | awk 'NR==1 || /apid|etcd|kubelet|cri|containerd/'
done
```

If local DNS does not resolve `sslip.io`, `just ingress-smoke-check` pins each hostname to `192.168.80.30` during the check.

To return to full sizing later, remove the smoke tfvars files and update capacity before applying again.
