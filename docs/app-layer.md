# GitOps App Layer

This repo keeps Terraform focused on cluster bootstrap and uses Argo CD for the beginner app layer.

## First Argo Sync

1. Push this repository to GitHub or another external Git provider.
2. Set `gitops_repo_url` in `terraform/platform/lab.auto.tfvars`.
3. Re-run the platform stage:

```bash
cd terraform/platform
terraform apply
```

4. Confirm the root app and child apps appear:

```bash
export KUBECONFIG="$(pwd)/../../_out/kubeconfig"
kubectl -n argocd get applications
```

The cluster overlay creates Argo apps for Longhorn, the lab StorageClass, Homarr, Uptime Kuma, Forgejo, monitoring, Loki, Alloy, AdGuard Home, and helper charts.

## Hostnames

Bootstrap access keeps using `sslip.io` on `192.168.80.30`.

Daily-use hostnames are:

- `rancher.lab.home.arpa`
- `argocd.lab.home.arpa`
- `longhorn.lab.home.arpa`
- `homarr.lab.home.arpa`
- `status.lab.home.arpa`
- `git.lab.home.arpa`
- `grafana.lab.home.arpa`
- `prometheus.lab.home.arpa`
- `adguard.lab.home.arpa`
- `whoami.lab.home.arpa`

## AdGuard Home

AdGuard Home exposes:

- UI through ingress on `adguard.lab.home.arpa`
- DNS through `192.168.80.31:53` TCP/UDP

The chart pre-seeds a minimal config so DNS works on first boot. Then add local rewrites in the UI:

- `rancher.lab.home.arpa -> 192.168.80.30`
- `argocd.lab.home.arpa -> 192.168.80.30`
- `longhorn.lab.home.arpa -> 192.168.80.30`
- `homarr.lab.home.arpa -> 192.168.80.30`
- `status.lab.home.arpa -> 192.168.80.30`
- `git.lab.home.arpa -> 192.168.80.30`
- `grafana.lab.home.arpa -> 192.168.80.30`
- `prometheus.lab.home.arpa -> 192.168.80.30`
- `adguard.lab.home.arpa -> 192.168.80.30`
- `whoami.lab.home.arpa -> 192.168.80.30`

Validate with:

```bash
dig @192.168.80.31 grafana.lab.home.arpa
dig @192.168.80.31 github.com
```

Then point a test client at `192.168.80.31` as its DNS server and confirm query logs appear in AdGuard.

## First Logins

Forgejo generates its admin secret in-cluster:

```bash
kubectl -n forgejo get secret forgejo-admin \
  -o jsonpath='{.data.username}' | base64 -d; echo
kubectl -n forgejo get secret forgejo-admin \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Grafana stores credentials in its release secret:

```bash
kubectl -n monitoring get secret monitoring-grafana \
  -o jsonpath='{.data.admin-user}' | base64 -d; echo
kubectl -n monitoring get secret monitoring-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Homarr and Uptime Kuma are intentionally light on bootstrap data. Create the first dashboards and monitors manually in the UI.

Suggested first Uptime Kuma monitors:

- `https://rancher.lab.home.arpa`
- `http://whoami.lab.home.arpa`
- `https://git.lab.home.arpa`
- `192.168.80.10:6443` as TCP
- `192.168.80.30:80` as TCP
- `192.168.80.31:53` as DNS

## Forgejo Runner

The `forgejo-runner` Argo app is created but not auto-synced. Bootstrap it after Forgejo is live.

1. In Forgejo, create a new runner in the UI and copy the displayed `uuid` and `token`.
2. Create the connection secret in Kubernetes:

```bash
kubectl -n forgejo create secret generic forgejo-runner-connection \
  --from-literal=FORGEJO_INSTANCE_URL=https://git.lab.home.arpa \
  --from-literal=FORGEJO_RUNNER_UUID='replace-me' \
  --from-literal=FORGEJO_RUNNER_TOKEN='replace-me'
```

3. Sync the runner app from Argo CD.

The runner is intentionally minimal and only advertises `lab-host:host` for beginner lint and test jobs. It does not build containers.

Example workflow:

```yaml
on:
  push:

jobs:
  shell-check:
    runs-on: lab-host
    steps:
      - uses: https://data.forgejo.org/actions/checkout@v4
      - run: uname -a
      - run: just validate
```
