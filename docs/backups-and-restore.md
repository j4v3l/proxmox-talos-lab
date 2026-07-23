# Backup and restore

PBS provides nightly VM recovery. It is not the only backup.

Use separate least-privilege credentials and encrypted/versioned buckets for:

- Terraform state and lock files.
- Longhorn recurring backups.
- Velero object/volume backups.
- CloudNativePG Barman Cloud WAL archives and nightly base backups.

Never reuse cluster, Proxmox, or runner credentials for backup storage.

Quarterly restore drill:

1. Restore Terraform state to an isolated backend key and run a read-only plan.
2. Restore a generic Longhorn volume into a disposable namespace and hash its contents.
3. Recover Forgejo PostgreSQL to a new CNPG cluster, attach a repository-storage restore, and perform clone/fsck.
4. Restore Pi-hole `/etc/pihole`, confirm the three managed lists/local records, then test DNS.
5. Restore a Velero namespace to an alternate name.

Record source backup timestamp, requested and measured RPO/RTO, checksums, commands, defects, and remediation. Readiness requires RPO ≤ 6h and RTO ≤ 4h.
