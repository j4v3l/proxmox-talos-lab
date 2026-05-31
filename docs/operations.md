# Operations

## Health Checks

After `terraform/infra` finishes:

```bash
export TALOSCONFIG="$(pwd)/../../_out/talosconfig"
talosctl get members --nodes 192.168.80.21 --endpoints 192.168.80.21
talosctl etcd members --nodes 192.168.80.21 --endpoints 192.168.80.21
for ip in 192.168.80.21 192.168.80.22 192.168.80.23 192.168.80.24 192.168.80.25; do
  talosctl services --nodes "$ip" --endpoints 192.168.80.21 | awk 'NR==1 || /apid|etcd|kubelet|cri|containerd/'
done
```

`talosctl health` can report a Kubernetes node matching error when the API VIP is present on the first control-plane node. The commands above verify the same core pieces explicitly: membership, etcd quorum, Talos API, container runtime, CRI, and kubelet health.

After `terraform/platform` finishes:

```bash
export KUBECONFIG="$(pwd)/../../_out/kubeconfig"
kubectl get nodes -o wide
kubectl -n kube-system get pods
kubectl -n metallb-system get ipaddresspools,l2advertisements
kubectl -n ingress-nginx get svc
kubectl -n cattle-system get pods
kubectl -n argocd get applications
kubectl -n longhorn-system get pods
```

## UI URLs

- Rancher: `http://rancher.192.168.80.30.sslip.io`
- Argo CD: `http://argocd.192.168.80.30.sslip.io`
- Longhorn: `http://longhorn.192.168.80.30.sslip.io`
- Sample app: `http://whoami.192.168.80.30.sslip.io`

Rancher uses the bootstrap password generated or supplied in `terraform/platform`.

## Network Checks

After capacity is fixed and the cluster is bootstrapped, run:

```bash
just post-bootstrap-check
just ingress-smoke-check
```

From the Caddy host at `192.168.10.128`, verify proxy reachability to ingress:

```bash
curl -I --connect-timeout 5 http://192.168.80.30
curl -kI --connect-timeout 5 https://192.168.80.30
```

## Destroy Order

Destroy platform resources before infrastructure:

```bash
cd terraform/platform
terraform destroy

cd ../infra
terraform destroy
```

Terraform is scoped to VMIDs `810-814`; it should not touch existing Proxmox VMs.
