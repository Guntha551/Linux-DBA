# 03 · Filesystem & Storage

**Goal:** Monitor space, find what is filling a disk, and add/extend storage for datafiles and backups safely.

---

## Step 1 — Check free space

```bash
$ df -h                 # size, used, available per filesystem
$ df -hT /u02           # one mount point, with filesystem type
$ df -i                 # INODE usage — a disk can be "full" with free space if inodes run out
```

**Tip:** Millions of tiny audit (`.aud`) or trace (`.trc`) files exhaust inodes. If `df -h` shows space but you get *"No space left on device"*, check `df -i`.

---

## Step 2 — Find what is using the space

```bash
$ du -sh /u01/app/oracle/*                 # size of each sub-directory
$ du -h --max-depth=1 /var/lib/pgsql | sort -hr | head
$ du -ah /backup | sort -hr | head -20     # 20 largest files/dirs
$ find / -xdev -type f -size +1G -exec ls -lh {} \; 2>/dev/null   # files >1 GB on this filesystem
```

| Option | Meaning |
|--------|---------|
| `-s` | summary total only |
| `-h` | human-readable sizes |
| `-x` / `-xdev` | stay on one filesystem (don't descend into other mounts) |
| `sort -hr` | sort human-readable sizes, largest first |

---

## Step 3 — Space used by deleted-but-open files

A classic: someone deletes a huge log file, but `df` still shows the disk full because the database process keeps it open.

```bash
# lsof +L1 | grep -i deleted
# lsof -nP | grep '(deleted)' | sort -k7 -n -r | head
```

**Fix:** Restart the process holding the file, or truncate it through `/proc`:

```bash
# : > /proc/<PID>/fd/<FD>      # ⚠️ truncates the open file to 0 bytes
```

The safer habit: **truncate** logs instead of deleting them:

```bash
$ > alert_ORCL.log            # or: truncate -s 0 alert_ORCL.log
```

---

## Step 4 — See disks and partitions

```bash
$ lsblk -f               # devices, filesystem types, UUIDs, mount points
# fdisk -l               # partition tables
# blkid                  # UUIDs (use these in /etc/fstab, not /dev/sdX)
```

---

## Step 5 — Add a new disk as a filesystem (step by step)

Example: new 500 GB disk `/dev/sdc` for `/u02` (datafiles).

```bash
# 1. Detect the new disk without rebooting (VMs)
# for h in /sys/class/scsi_host/host*; do echo "- - -" > $h/scan; done
# lsblk

# 2. Create a physical volume, volume group and logical volume (LVM)
# pvcreate /dev/sdc
# vgcreate vg_data /dev/sdc
# lvcreate -n lv_u02 -l 100%FREE vg_data

# 3. Create an XFS filesystem
# mkfs.xfs /dev/vg_data/lv_u02

# 4. Mount it
# mkdir -p /u02
# mount /dev/vg_data/lv_u02 /u02

# 5. Make it permanent
# echo '/dev/mapper/vg_data-lv_u02  /u02  xfs  defaults,noatime  0 0' >> /etc/fstab
# mount -a            # tests fstab — an error here would break the next boot!

# 6. Hand it to the DB owner
# chown oracle:oinstall /u02
```

**Why LVM:** it lets you grow the filesystem later without downtime (Step 6). `noatime` avoids a metadata write on every read, which helps database I/O.

---

## Step 6 — Extend a filesystem online

```bash
# pvs; vgs; lvs                              # current LVM layout and free space
# pvcreate /dev/sdd                          # new disk
# vgextend vg_data /dev/sdd                  # add it to the volume group
# lvextend -r -L +200G /dev/vg_data/lv_u02   # grow LV AND filesystem (-r) in one step
$ df -h /u02
```

Manual resize if you forget `-r`:

```bash
# xfs_growfs /u02                 # XFS (grow only — XFS cannot shrink)
# resize2fs /dev/vg_data/lv_u02   # ext4
```

---

## Step 7 — Mount options and NFS for backups

```bash
$ mount | grep /u02
$ findmnt /backup
# mount -t nfs -o rw,bg,hard,nointr,rsize=1048576,wsize=1048576,tcp,vers=3,timeo=600 nas01:/export/backup /backup
```

The options above are Oracle's recommendation for RMAN backups on NFS. `hard` means I/O waits rather than failing silently — you never want a backup written with silent errors.

---

## Step 8 — Unmount

```bash
# umount /backup
# fuser -vm /backup       # "target is busy"? This shows who is using it
# lsof +D /backup
```

---

## Step 9 — Filesystem check / health

```bash
# xfs_repair -n /dev/vg_data/lv_u02     # read-only check (filesystem must be unmounted)
# smartctl -a /dev/sda                  # physical disk health (smartmontools)
# dmesg -T | grep -i -E 'error|i/o|xfs'  # kernel-reported disk errors
```
