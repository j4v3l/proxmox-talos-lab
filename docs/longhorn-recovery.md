# Longhorn recovery boundary

The legacy volumes are faulted single-replica volumes whose only replicas were on one pressured worker. Do not attempt bulk live salvage.

1. Stop and back up VMIDs 810-814 to PBS.
2. Clone recovery candidates offline.
3. Capture `just longhorn-recovery-capture`.
4. Extract valuable data only from offline clones.
5. Rebuild cleanly on dedicated 250 GiB worker disks.

Production uses `longhorn-2r` with two replicas, `Retain`, best-effort locality, replica anti-affinity, a 20% free-space floor, six-hour snapshots, and nightly off-host backups. A successful restore—not a green backup job—is the acceptance criterion.
