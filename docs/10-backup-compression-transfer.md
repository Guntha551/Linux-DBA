# 10 · Backup, Compression & File Transfer

**Goal:** Archive, compress, verify and move database backups between servers.

---

## Step 1 — tar: bundle files and directories

```bash
$ tar -cvf  oh_backup.tar      $ORACLE_HOME            # create
$ tar -czvf pgconf_$(date +%F).tar.gz /var/lib/pgsql/16/data/*.conf   # create + gzip
$ tar -tvf  oh_backup.tar | head                       # list contents
$ tar -xvf  oh_backup.tar -C /u01/restore              # extract into a directory
$ tar -xzvf pgconf_2026-09-24.tar.gz etc/postgresql.conf   # extract one file
```

| Flag | Meaning |
|------|---------|
| `c` / `x` / `t` | create / extract / list |
| `z` / `j` / `J` | gzip / bzip2 / xz |
| `v` | verbose |
| `f` | archive file name |
| `-C` | target directory |
| `p` | preserve permissions (default for root) |

**Tip:** Always tar `$ORACLE_HOME` before applying a patch (OPatch rollback isn't always clean).

---

## Step 2 — Compression

```bash
$ gzip   expdp_full.dmp          # -> expdp_full.dmp.gz (replaces original)
$ gzip -k -9 file                # keep original, max compression
$ gunzip expdp_full.dmp.gz
$ pigz -p 8 expdp_full.dmp       # parallel gzip — much faster on multi-core servers
$ zstd -T0 -3 backup.tar         # modern, fast compression; unzstd to decompress
$ xz -T0 backup.tar              # best ratio, slowest
$ zcat file.gz | less            # read without decompressing to disk
```

Streaming (no intermediate file):

```bash
$ pg_dump -Fp mydb | gzip > mydb_$(date +%F).sql.gz
$ mysqldump --single-transaction --all-databases | zstd > all_$(date +%F).sql.zst
$ gunzip -c mydb.sql.gz | psql mydb                  # restore from compressed file
```

---

## Step 3 — Copy between servers: scp

```bash
$ scp expdp_full.dmp oracle@dbhost02:/u02/dpdump/
$ scp -r /backup/rman oracle@dbhost02:/backup/       # directory
$ scp -P 2222 file user@host:/tmp/                   # non-default SSH port
$ scp -l 400000 big.dmp host:/backup/                # limit bandwidth (Kbit/s)
```

---

## Step 4 — rsync: the DBA's best friend

```bash
$ rsync -avP /backup/rman/ oracle@dbhost02:/backup/rman/
$ rsync -avP --dry-run /src/ host:/dst/              # show what WOULD be copied
$ rsync -av --delete /src/ host:/dst/                # ⚠️ mirror: deletes files at dst missing in src
$ rsync -avP --bwlimit=50000 big.dmp host:/backup/   # limit to ~50 MB/s
$ rsync -avz -e "ssh -p 2222" /src/ host:/dst/       # compress in transit, custom ssh port
```

| Flag | Meaning |
|------|---------|
| `-a` | archive: recursive + keep permissions, owner, times, links |
| `-v` | verbose |
| `-P` | progress + **resume partial transfers** (vital for 100 GB dumps over a WAN) |
| `-z` | compress during transfer (skip for already-compressed files) |

**Trailing slash matters:** `src/` copies the *contents*; `src` copies the directory itself.

---

## Step 5 — Passwordless SSH (for scripts, RAC, Data Guard)

```bash
$ ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519      # generate key (once)
$ ssh-copy-id oracle@dbhost02                             # install public key on target
$ ssh oracle@dbhost02 hostname                            # should not ask for a password
$ chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys      # SSH refuses keys with loose permissions
```

---

## Step 6 — Verify backups (checksums)

```bash
$ sha256sum expdp_full.dmp > expdp_full.dmp.sha256
$ sha256sum -c expdp_full.dmp.sha256       # on the destination: prints "OK"
$ gzip -t file.gz && echo OK               # test gzip integrity
$ tar -tzf backup.tar.gz > /dev/null && echo OK
```

---

## Step 7 — Split / join very large files

```bash
$ split -b 10G -d expdp_full.dmp expdp_full.dmp.part_       # 10 GB chunks
$ cat expdp_full.dmp.part_* > expdp_full.dmp                 # re-assemble
```

(Better: use `FILESIZE=10G` in Data Pump or `MAXPIECESIZE` in RMAN.)

---

## Step 8 — Filesystem-level snapshot backup (LVM)

```bash
# lvcreate -s -n snap_u02 -L 50G /dev/vg_data/lv_u02    # instant snapshot (DB in backup mode / crash-consistent)
# mount -o ro,nouuid /dev/vg_data/snap_u02 /mnt/snap     # nouuid needed for XFS
$ rsync -a /mnt/snap/ /backup/u02_copy/
# umount /mnt/snap && lvremove -y /dev/vg_data/snap_u02
```

For Oracle, wrap it with `ALTER DATABASE BEGIN BACKUP;` / `END BACKUP;`; for PostgreSQL use `pg_backup_start()` / `pg_backup_stop()` or rely on WAL for crash consistency.
