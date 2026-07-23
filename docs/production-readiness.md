# Production readiness gates

Production is blocked until every item is evidenced.

## Infrastructure

- 64 GiB or more installed RAM; steady-state headroom above 20%; host swap zero.
- Dedicated 1 TiB+ SSD/NVMe; root and production datastore below 75%.
- Stopped PBS backups and offline recovery clones verified before rebuild.
- Trusted Proxmox CA and privilege-separated Terraform token.
- Encrypted/versioned remote Terraform backend with native lock files.

## Cluster and delivery

- `just ci` passes locally, in Forgejo, and in GitHub.
- Five nodes survive one-at-a-time worker/control-plane reboots.
- Cilium connectivity and Gateway API smoke/conformance tests pass.
- Every Application is `Synced/Healthy` for 24 hours, uses a non-default project, and shows no repeated self-heal.
- Protected `main`, required CI, signed/linear history, no direct/force push or deletion.
- GitHub Pro (or an equivalent plan) enabled for private-repository branch
  protection and secret-scanning push protection on `j4v3l/talos-apps`.
  GitHub currently returns HTTP 403/422 for those controls on the private
  repository; Dependabot alerts and automated security fixes are enabled.

## Data and identity

- Every production PVC has two healthy Longhorn replicas and at least 20% disk free.
- Independent off-host Longhorn, Velero, CloudNativePG, and Terraform-state backups are current.
- Authentik MFA protects OIDC applications; proxy outposts protect UIs without native OIDC.
- All `*.lab.home.arpa` certificates validate from LAN/VPN clients against the private root.

## DNS and Forgejo

- TCP/UDP DNS works independently through `.31` and `.32`; either can be stopped without client outage.
- DNSSEC/Unbound, declarative records/lists, daily jittered gravity, and selective Nebula Sync pass.
- Cached DNS p95 is below 10 ms with zero errors at 100 qps.
- Forgejo HTTPS/SSH/LFS/packages/actions/metrics pass.
- The repository-scoped runner completes CI inside a job container and cannot reach cluster management or backup endpoints.

## Restore acceptance

Document real restores of one Forgejo repository/database, one generic PVC, Pi-hole configuration, one Velero namespace, and the Terraform backend. Required RPO is six hours; tested RTO is four hours.
