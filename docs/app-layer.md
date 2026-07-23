# Hybrid GitOps

GitHub `j4v3l/proxmox-talos-lab` is the public bootstrap/DR source. Forgejo `j4v3l/talos-apps` is authoritative for applications, and private GitHub `j4v3l/talos-apps` is its one-way push mirror.

Terraform installs only Gateway API CRDs, Cilium, Argo CD/KSOPS, and `talos-bootstrap`. The bootstrap Application creates exact `bootstrap`, `platform`, and `apps` AppProjects and pinned two-source Applications. No Application uses `default`.

Protected `main` is the only deployment branch. Platform applications that own CRDs, storage, databases, or identity have no automated sync policy. Monitoring and Pi-hole may self-heal; Pi-hole pruning is disabled to protect its retained PVC.

## Private repository bootstrap

1. Create a read-only Forgejo deploy key for Argo CD.
2. Inject the repository Secret directly into `argocd`; never put it in Terraform.
3. Run `just bootstrap-sops-age` to inject the age identity.
4. Add only SOPS ciphertext under `talos-apps/secrets`.
5. Manually sync platform CRDs/controllers in wave order, then `platform-manifests`, databases, identity, Forgejo, and Pi-hole.

The dedicated runner is registered to a repository, has capacity one, and uses rootless Podman job containers. It has no host label and no cluster, Proxmox, Talos, or backup credential.
