# 09 · Kernel Parameters, Limits & HugePages

**Goal:** Configure the Linux kernel and resource limits the way database vendors recommend.

---

## Step 1 — View kernel parameters

```bash
$ sysctl -a | grep -E 'shm|sem|file-max|swappiness|overcommit'
$ sysctl kernel.shmmax
$ cat /proc/sys/kernel/sem
$ ipcs -lm        # shared memory limits
$ ipcs -m         # current shared memory segments (SGA / shared_buffers)
$ ipcs -s         # semaphores
```

---

## Step 2 — Recommended database settings

Create a dedicated file (easier to audit than editing `/etc/sysctl.conf`):

```bash
# vi /etc/sysctl.d/97-database.conf
```

```ini
# --- shared memory (Oracle; harmless for PG/MySQL) ---
# shmmax: max single segment in bytes - at least the SGA size
kernel.shmmax = 4398046511104
# shmall: total shared memory in 4 KB PAGES
kernel.shmall = 1073741824
kernel.shmmni = 4096
# SEMMSL SEMMNS SEMOPM SEMMNI
kernel.sem = 250 32000 100 128

# --- files and network ---
fs.file-max = 6815744
fs.aio-max-nr = 1048576
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576

# --- memory behaviour ---
# swap only as a last resort
vm.swappiness = 1
vm.dirty_background_ratio = 3
vm.dirty_ratio = 10
# PostgreSQL recommendation to avoid the OOM killer - test first, it can cause
# "cannot allocate memory" errors if overcommit_ratio is too low
vm.overcommit_memory = 2
vm.overcommit_ratio = 90
```

> **Note:** sysctl files do not allow comments at the end of a line — keep comments on their own line.

Apply and verify:

```bash
# sysctl --system              # load all files in /etc/sysctl.d
# sysctl -p /etc/sysctl.d/97-database.conf
$ sysctl vm.swappiness
```

**Tip:** On Oracle Linux, `dnf install oracle-database-preinstall-19c` (or `-23ai`) creates the `oracle` user and sets all of these automatically.

---

## Step 3 — User resource limits (ulimit)

```bash
$ ulimit -a         # all soft limits for the current shell
$ ulimit -Hn        # hard limit: open files
$ ulimit -Su        # soft limit: max user processes
$ cat /proc/<PID>/limits    # what a RUNNING process actually got
```

Set them in `/etc/security/limits.d/99-database.conf`:

```
oracle   soft   nofile    1024
oracle   hard   nofile    65536
oracle   soft   nproc     16384
oracle   hard   nproc     16384
oracle   soft   stack     10240
oracle   hard   stack     32768
oracle   soft   memlock   unlimited      # required for HugePages
oracle   hard   memlock   unlimited
mysql    soft   nofile    65535
mysql    hard   nofile    65535
```

Log out and in again, then check with `ulimit -a`.

**⚠️ systemd services ignore limits.conf.** For PostgreSQL/MySQL started by systemd use an override:

```bash
# systemctl edit mysqld
[Service]
LimitNOFILE=65535
LimitMEMLOCK=infinity
# systemctl daemon-reload && systemctl restart mysqld
```

---

## Step 4 — Transparent HugePages (disable for databases)

Oracle, PostgreSQL, MySQL and MongoDB all recommend disabling THP — it causes latency spikes.

```bash
$ cat /sys/kernel/mm/transparent_hugepage/enabled
always madvise [never]           # the value in brackets is active
```

Disable permanently:

```bash
# grubby --update-kernel=ALL --args="transparent_hugepage=never"    # RHEL/OL 8-9
# reboot
```

(Ubuntu: add `transparent_hugepage=never` to `GRUB_CMDLINE_LINUX` in `/etc/default/grub`, then `update-grub`.)

---

## Step 5 — Configure (static) HugePages

HugePages (2 MB pages) make the SGA / shared_buffers non-swappable and reduce page-table overhead — essential for SGAs larger than ~8 GB.

**Calculate the number of pages:**

```
nr_hugepages = (SGA or shared_buffers size in MB / 2) + a small margin
Example: SGA 24 GB -> 24576 / 2 = 12288 -> set 12300
```

For PostgreSQL, ask the server itself (PG 15+):

```bash
$ postgres -D $PGDATA -C shared_memory_size_in_huge_pages
```

Configure:

```bash
# echo "vm.nr_hugepages = 12300" >> /etc/sysctl.d/97-database.conf
# sysctl --system
$ grep Huge /proc/meminfo
HugePages_Total:   12300
HugePages_Free:    12300      # after the DB starts this should drop close to 0
HugePages_Rsvd:        0
Hugepagesize:       2048 kB
```

Database side:
- Oracle: `USE_LARGE_PAGES = ONLY` (instance will refuse to start without enough pages) — and `memlock` must be unlimited. **Do not use** `MEMORY_TARGET` with HugePages.
- PostgreSQL: `huge_pages = on`.
- MySQL: `large_pages = ON`.

---

## Step 6 — Tuned profiles

```bash
# dnf install -y tuned
# tuned-adm list
# tuned-adm profile throughput-performance      # good baseline for DB servers
$ tuned-adm active
```

---

## Step 7 — Time synchronisation (critical for RAC, replication, Data Guard)

```bash
$ timedatectl
$ chronyc tracking            # offset from the time source
$ chronyc sources -v
```
