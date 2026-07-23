# Repository incident response

Terraform plans and a historical Homarr secret were committed to a public repository. Treat Talos machine secrets, client certificates, kubeconfig, Rancher/Homarr credentials, Forgejo credentials, internal CA material, and the Proxmox token as exposed.

Required sequence:

1. Preserve the dirty tree and Git history in an encrypted offline bundle.
2. Remove `tfplan*` and the historical Homarr Secret from every branch/tag with `git filter-repo`.
3. Force-push rewritten `main` and `dev`, invalidate old clones, and publish the new root commit IDs.
4. Rebuild Talos to rotate all generated machine/client/bootstrap material.
5. Rotate Proxmox, Argo, Rancher, Homarr, Forgejo, mirror, SOPS/bootstrap, and CA intermediate credentials.
6. Run Gitleaks across every rewritten ref before unblocking merges.

History cleanup reduces accidental exposure; it does not unexpose a secret. Rotation is mandatory.
