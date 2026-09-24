# 16 · Troubleshooting Scenarios (step by step)

Real incidents, and the order of commands a DBA runs to solve them.

---

## Scenario 1 — "The database is slow"

**Step 1. Is the whole server busy?**

```bash
$ uptime                     # load average vs. nproc
$ vmstat 2 5                 # r (CPU queue), si/so (swap), wa (I/O wait)
```

**Step 2. Decide which resource is the bottleneck.**

| Symptom | Bottleneck | Next step |
|---------|-----------|-----------|
| `us`+`sy` near 100%, `r` > CPU count | CPU | `top`, `ps --sort=-%cpu`, map PID → SQL |
| `si`/`so` > 0, `available` low | Memory | `ps --sort=-rss`, check SGA/buffer sizes, OOM in `dmesg` |
| `wa` high, many `b` processes | Disk | `iostat -xz 5`, `iotop -oP` |
| All low | Not the OS | Look inside the DB: locks, waits, plans |

**Step 3. Find the process and map it to the database session** (see [04](04-memory-and-cpu.md#step-7--top-cpu-consumers-and-mapping-to-db-sessions)).

**Step 4. Check history** to see when it started:

```bash
$ sar -u -s 08:00:00 -e 12:00:00
$ sar -q                         # run-queue / load history
```

---

## Scenario 2 — "Filesystem is 100% full"

```bash
$ df -h                                              # 1. which filesystem?
$ df -i                                              # 2. space or inodes?
$ du -xh --max-depth=1 /u01 | sort -hr | head        # 3. drill down level by level
$ find /u01 -xdev -type f -size +500M -mmin -60 -ls  # 4. big files created in the last hour
# lsof +L1                                           # 5. deleted-but-open files
```

Then, by cause:

| Culprit | Safe action |
|---------|-------------|
| Archive logs (Oracle) | RMAN `backup archivelog all delete input` |
| `pg_wal` (PostgreSQL) | fix archiving / drop dead replication slot — never `rm` |
| Binlogs (MySQL) | `PURGE BINARY LOGS BEFORE ...` |
| Trace / audit files | `find ... -mtime +7 -delete`, `adrci purge` |
| Huge alert/listener log | `> file` (truncate), set up logrotate |
| Old dumps / backups | move to backup storage, then delete |

---

## Scenario 3 — "Application cannot connect"

```bash
# On the DB server
$ ps -ef | grep -E '[t]nslsnr|[p]ostgres|[m]ysqld'   # 1. database/listener running?
# ss -tlnp | grep -E '1521|5432|3306'                # 2. listening, on which IP?
$ lsnrctl status  |  pg_isready  |  mysqladmin ping  # 3. DB-level check
# firewall-cmd --list-all                            # 4. port open?
# ausearch -m avc -ts recent                         # 5. SELinux blocking?

# On the client
$ getent hosts dbhost01                              # 6. DNS
$ nc -zv dbhost01 5432                               # 7. TCP path
```

Then check database authentication: `pg_hba.conf`, MySQL `user@host`, Oracle `sqlnet.ora` / invited nodes, and the DB log for `FATAL` / `Access denied` / `ORA-12514`.

---

## Scenario 4 — "Database won't start"

```bash
$ tail -50 <alert/error log>            # 1. the real error is almost always here
$ df -h; df -i                          # 2. full disk?
$ ls -ld <data dir>                     # 3. owner / permissions (PG needs 700)
$ ipcs -m; ipcs -s                      # 4. leftover shared memory / semaphores after a crash
$ grep Huge /proc/meminfo               # 5. enough HugePages (Oracle USE_LARGE_PAGES=ONLY)?
$ ulimit -a                             # 6. limits for the DB user
# journalctl -u postgresql-16 -n 50     # 7. systemd view
```

Stale IPC after a crash (only when **no** instance process is running):

```bash
$ ipcs -m | awk '$3=="oracle"{print $2}'       # list segments owned by oracle
$ ipcrm -m <shmid>                              # ⚠️ remove a stale segment
$ rm /var/lib/pgsql/16/data/postmaster.pid      # ⚠️ PG only, only if NO postgres process exists
```

---

## Scenario 5 — "Instance crashed / processes disappeared"

```bash
# dmesg -T | grep -i -E 'killed process|out of memory'   # OOM killer?
# journalctl -k --since "2 hours ago"
$ last -x | head                                         # reboot or shutdown?
$ grep -i -E 'terminating|shutdown|crash' <alert log>
# ls -ltr /var/crash/ /var/lib/systemd/coredump/         # core dumps
```

---

## Scenario 6 — "Server is swapping heavily"

```bash
$ free -h
$ vmstat 2 5                                       # si/so
$ for f in /proc/[0-9]*/status; do awk '/^Name|^VmSwap/{printf "%s ", $2} END{print ""}' $f; done 2>/dev/null | sort -k2 -nr | head
#   -> processes using the most swap
$ grep -E 'HugePages_(Total|Free)' /proc/meminfo  # HugePages allocated but unused = wasted RAM
$ sysctl vm.swappiness
```

Typical fixes: reduce SGA/`shared_buffers`/`innodb_buffer_pool_size` or `work_mem`, correct the HugePages count, lower connection count (pooling), set `vm.swappiness=1`.

---

## Scenario 7 — "Backup copy between servers is too slow"

```bash
$ iperf3 -c target -P 4              # 1. raw network bandwidth
$ ethtool eth0 | grep Speed          # 2. link speed
$ iostat -xz 5                       # 3. source/target disk saturated?
$ rsync -avP --no-compress ...       # 4. skip -z for already-compressed files
$ pigz / zstd -T0                    # 5. use parallel compression
```
