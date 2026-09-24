# 04 · Memory & CPU

**Goal:** Decide whether the server is short of memory or CPU, and which process is responsible.

---

## Step 1 — Memory at a glance

```bash
$ free -h
              total        used        free      shared  buff/cache   available
Mem:           62Gi        38Gi       1.2Gi        20Gi        23Gi        3.1Gi
Swap:          16Gi       2.0Gi        14Gi
```

| Column | Meaning |
|--------|---------|
| `used` | memory used by processes |
| `shared` | shared memory — Oracle SGA / PostgreSQL shared_buffers live here |
| `buff/cache` | page cache; reclaimable when apps need RAM |
| `available` | **the real number to watch** — memory that can be given to new work |

**Rule of thumb:** `available` < 10% of total **and** swap `used` growing = memory pressure.

---

## Step 2 — Detailed memory breakdown

```bash
$ cat /proc/meminfo
$ grep -E 'MemTotal|MemAvailable|Cached|SwapTotal|SwapFree|Shmem|HugePages_|Hugepagesize|Committed_AS|CommitLimit' /proc/meminfo
```

- `Shmem` — size of shared memory segments in normal pages.
- `HugePages_Total / HugePages_Free` — see [09 Kernel parameters](09-kernel-parameters-hugepages.md).
- `Committed_AS` > `CommitLimit` — the system has promised more memory than it has.

---

## Step 3 — Is the server swapping right now?

```bash
$ vmstat 5 5          # 5 samples, 5 seconds apart
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 3  0 204800 1200000 ...           0    0   120   800 ...      25  5 68  2  0
```

| Column | What to look for |
|--------|------------------|
| `r` | runnable processes; consistently > CPU count = CPU bottleneck |
| `b` | processes blocked on I/O |
| `si` / `so` | swap in / out per second; **non-zero and sustained = memory shortage** |
| `us` / `sy` | user / system CPU % |
| `wa` | CPU waiting on I/O — high = storage bottleneck |
| `st` | stolen by the hypervisor (VMs) — high = noisy neighbour |

```bash
$ sar -r 1 5        # memory utilisation (sysstat package)
$ sar -W 1 5        # swapping activity
$ swapon --show     # swap devices
```

---

## Step 4 — Which process uses the most memory?

```bash
$ ps aux --sort=-rss | head -15               # sorted by resident memory
$ ps -eo pid,user,rss,vsz,comm --sort=-rss | head
$ top -o %MEM                                  # interactive, sorted by memory
$ smem -rs pss | head                          # (if installed) proportional usage — correct for shared memory
```

**Note:** Every Oracle/PostgreSQL process maps the shared memory region, so summing RSS over-counts. Use `smem`'s PSS or check `/proc/<pid>/smaps_rollup`.

---

## Step 5 — Was a process killed by the OOM killer?

```bash
# dmesg -T | grep -i -E 'out of memory|killed process'
# journalctl -k | grep -i oom
```

If the database postmaster/`ora_pmon` was killed, the instance crashed. For PostgreSQL, protect the postmaster:

```bash
# echo -1000 > /proc/$(head -1 /var/lib/pgsql/16/data/postmaster.pid)/oom_score_adj
```

and set `vm.overcommit_memory = 2` (see chapter 09).

---

## Step 6 — CPU at a glance

```bash
$ top            # press 1 = per-CPU view, P = sort by CPU, M = sort by memory, c = full command, q = quit
$ htop           # friendlier (install separately)
$ mpstat -P ALL 5 2      # per-CPU usage — spots one pegged core
$ sar -u 5 5             # CPU utilisation history
$ sar -u -f /var/log/sa/sa$(date -d yesterday +%d)   # yesterday's CPU (sysstat keeps ~1 month)
```

`top` header line:

```
%Cpu(s): 72.1 us,  4.3 sy,  0.0 ni, 20.2 id,  3.1 wa,  0.0 hi,  0.3 si,  0.0 st
```

---

## Step 7 — Top CPU consumers and mapping to DB sessions

```bash
$ ps -eo pid,user,%cpu,%mem,etime,cmd --sort=-%cpu | head -15
$ pidstat -u 5 3             # per-process CPU over time
$ top -H -p <PID>            # threads inside one process (MySQL is multi-threaded)
```

Map an OS PID to a database session:

```sql
-- Oracle
SELECT s.sid, s.serial#, s.username, s.sql_id FROM v$session s JOIN v$process p ON s.paddr = p.addr WHERE p.spid = '<PID>';
-- PostgreSQL
SELECT pid, usename, state, query FROM pg_stat_activity WHERE pid = <PID>;
-- MySQL 8
SELECT * FROM performance_schema.threads WHERE THREAD_OS_ID = <TID>;
```

---

> For a full step-by-step investigation of one busy process (user, command, threads, system calls, SQL), see [17 High-CPU process investigation](17-high-cpu-process-investigation.md).

---

## Step 8 — Clear the page cache (testing only)

```bash
# sync; echo 3 > /proc/sys/vm/drop_caches     # ⚠️ never on busy production — causes an I/O storm
```

Useful when benchmarking cold-cache query performance.
