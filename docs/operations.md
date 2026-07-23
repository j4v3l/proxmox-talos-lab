# Operations

Routine verification:

```bash
just ci
just post-bootstrap-check
LAB_CA_FILE=/secure/lab-root-ca.crt just gateway-smoke-check
LAB_CA_FILE=/secure/lab-root-ca.crt OPNSENSE_CROWDSEC_VERIFIED=true just production-sanity
./scripts/dns-benchmark.sh
```

Argo CD must remain `Synced/Healthy` for 24 hours without a self-heal loop. Check:

```bash
kubectl -n argocd get applications
kubectl -n argocd get applications -o json |
  jq -r '.items[] | [.metadata.name,.spec.project,.status.sync.status,.status.health.status] | @tsv'
kubectl -n gateway-system get gateway,httproute
kubectl -n longhorn-system get volumes.longhorn.io,nodes.longhorn.io,recurringjobs.longhorn.io
kubectl -A get clusters.postgresql.cnpg.io,scheduledbackups.postgresql.cnpg.io
```

Production URLs are `https://{argocd,auth,git,longhorn,pihole,pihole-secondary}.lab.home.arpa`. Bootstrap `sslip.io` is emergency-only.

Forgejo is authoritative for `j4v3l/talos-apps`; private GitHub is its one-way
off-site mirror. After Forgejo is rebuilt, create a repository-scoped Forgejo
token and a fine-grained GitHub token limited to `j4v3l/talos-apps`, then run:

```bash
export FORGEJO_TOKEN='read from the operator password manager'
export GITHUB_MIRROR_TOKEN='read from the operator password manager'
./scripts/configure-forgejo-mirror.sh
```

The script creates the private Forgejo repository if necessary, seeds `main`,
installs the repository-scoped Actions secret, and protects Forgejo `main` with
signed commits and required CI. Forgejo Actions force-updates only GitHub
`mirror/forgejo-main`; GitHub opens a PR from that branch to its protected
`main`. Tokens are not written to Git or Terraform state.

Never repair storage, rotate the private CA, force-push protected branches, or apply Terraform from CI. Major/CRD/database/storage changes require a reviewed plan, a backup-freshness check, and a manual Argo sync window.
