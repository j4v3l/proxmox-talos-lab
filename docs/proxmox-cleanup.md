# Proxmox Cleanup Notes

These are manual inspection commands only. Do not delete files unless you have confirmed they are unused.

## List Talos ISO Files

```bash
ssh root@192.168.0.119 'find /var/lib/vz/template/iso -maxdepth 1 -type f -iname "*talos*" -print'
```

## Check VM CD-ROM References

```bash
ssh root@192.168.0.119 'for id in $(qm list | awk "NR>1 {print \$1}"); do echo "VM $id"; qm config "$id" | grep -E "^(ide|sata|scsi)[0-9]+:.*iso" || true; done'
```

## Remove an Unused ISO

Only after confirming no VM references the file:

```bash
ssh root@192.168.0.119 'rm -i /var/lib/vz/template/iso/OLD-TALOS.iso'
```

