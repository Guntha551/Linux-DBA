# 17 · Investigating a High-CPU Process

**Goal:** When CPU is high, answer four questions in order:

1. **Is** the CPU really busy, and on which CPUs?
2. **Which process** is using it, and **which user** owns it?
3. **Which command** is it: full command line, program, parent, how it was started?
4. **What is it doing**: which threads, system calls and functions, and which database session and SQL?

Most commands work as a normal user for your own processes. Run them as `root` (`#`) to see everyone's processes. Install the extra tools once:

```bash
# dnf install -y sysstat procps-ng psmisc strace perf gdb htop    # RHEL / OL / Rocky
# apt install -y sysstat procps psmisc strace linux-tools-generic gdb htop   # Ubuntu
```

---

## Step 1 — Confirm the CPU is really busy

```bash
$ nproc                  # number of CPUs, needed to judge the load
$ uptime                 # load average (1, 5, 15 min)
$ vmstat 2 5             # r = run queue, us/sy/id/wa/st = CPU split
$ mpstat -P ALL 2 3      # per-CPU view: one CPU at 100% = single-threaded process
$ sar -u 2 5             # same numbers; sar -u alone shows today's history
```

How to read it:

| What you see | Meaning |
|--------------|---------|
| `id` near 0, `r` > `nproc` | CPU is saturated: processes are queuing for CPU |
| `us` high | application / database code (SQL execution, sorting, hashing) |
| `sy` high | kernel work: many system calls, context switches, memory management |
| `wa` high but `us`+`sy` low | **not a CPU problem**: processes wait on disk (see [06](06-disk-io-performance.md)) |
| `st` high (VMs) | the hypervisor is taking CPU away (a neighbour VM or an over-committed host) |
| One CPU at 100% in `mpstat`, others idle | a single-threaded process (one Oracle/PostgreSQL session) |

---

## Step 2 — Find the top CPU processes

### 2a. `top`: the live view

```bash
$ top -c -o %CPU
```

Keys inside `top`:

| Key | Action |
|-----|--------|
| `P` | sort by CPU |
| `c` | show the full command line |
| `1` | show each CPU separately |
| `u` then a user name | show one user only |
| `H` | show threads instead of processes |
| `V` | tree view (parent/child) |
| `k` then a PID | kill (⚠️ see Step 8 first) |
| `q` | quit |

Non-interactive (for scripts, email or tickets):

```bash
$ top -b -n 1 -c -o %CPU | head -20
# More accurate: 2 samples 5 s apart, keep only the second one
$ top -b -d 5 -n 2 -c -o %CPU | awk '/^top -/{n++} n==2' | head -25
```

### 2b. `ps`: sorted snapshot with the columns you choose

```bash
$ ps -eo pid,ppid,user,%cpu,%mem,stat,etime,time,args --sort=-%cpu | head -15
```

| Column | Meaning |
|--------|---------|
| `pid` / `ppid` | process ID / parent process ID |
| `user` | owner of the process |
| `%cpu` | ⚠️ **average over the process's whole life**, not the current usage |
| `stat` | `R` running, `S` sleeping, `D` waiting on I/O |
| `etime` | how long it has been running (`[[dd-]hh:]mm:ss`) |
| `time` | total CPU time used so far |
| `args` | full command line |

**Important:** Because `ps %cpu` is a lifetime average, a process that has run for 30 days and just started spinning shows a low `%cpu`. Use `top` or `pidstat` (below) for the **current** usage.

### 2c. `pidstat`: current CPU per process, with user and command

```bash
$ pidstat -u -U -l 5 1          # one 5-second sample
#   -u  CPU stats   -U  show user NAME   -l  full command line
```

```
Average:   USER       PID    %usr %system  %guest   %wait    %CPU   CPU  Command
Average:   oracle    48213   97.60    1.20    0.00    0.40   98.80     -  oracleORCL (LOCAL=NO)
Average:   postgres  30211   45.00   30.00    0.00    2.00   75.00     -  postgres: app appdb 10.0.0.21(51234) SELECT
```

`%usr` vs `%system` shows immediately whether the process burns CPU in its own code or inside the kernel.

### 2d. Other tools

```bash
$ htop                 # colour view, F4 filter, F5 tree, F6 sort, u = choose user
$ atop 5               # also records history: atop -r /var/log/atop/atop_YYYYMMDD
```

---

## Step 3 — Which user is using the CPU?

The `USER` column in `top`, `ps` and `pidstat` already shows the owner of each process. To see the **total per user**:

```bash
# Total %CPU per user (lifetime average, quick overview)
$ ps -eo user:20,%cpu --no-headers | awk '{cpu[$1]+=$2} END {for (u in cpu) printf "%-20s %6.1f\n", u, cpu[u]}' | sort -k2 -nr | head

# Current %CPU per user (5-second sample)
$ pidstat -u -U 5 1 | awk '/^Average/ && $2 != "USER" {cpu[$2]+=$8} END {for (u in cpu) printf "%-15s %6.1f\n", u, cpu[u]}' | sort -k2 -nr
#   ($8 = %CPU on sysstat 11.5+. Older versions have no %wait column: use $7.)

# Processes of one user only
$ top -c -u oracle
$ ps -u postgres -o pid,%cpu,etime,args --sort=-%cpu | head
```

**Note for DBAs:** On a database server almost everything runs as `oracle`, `postgres` or `mysql`. The OS user tells you *which database* is busy. The **database** user and the application come from Step 7.

Who is logged in and what they are running:

```bash
$ w                            # logged-in users, their idle time and current command
$ who -a
$ cat /proc/<PID>/loginuid     # UID of the person who logged in, even after su/sudo
$ getent passwd <UID>          # turn that UID into a name
```

---

## Step 4 — Which command is it? (full details for one PID)

Set the PID once and reuse it:

```bash
$ PID=48213
```

**Full command line, owner, start time and CPU used**

```bash
$ ps -o pid,ppid,user,%cpu,%mem,stat,lstart,etime,time,args -p $PID
$ ps -fp $PID
$ tr '\0' ' ' < /proc/$PID/cmdline; echo      # exact arguments, even when very long
```

`lstart` is the exact date and time the process started. Compare it with when the CPU problem began.

**Which program and which directory**

```bash
$ readlink /proc/$PID/exe      # the binary on disk, e.g. /u01/app/oracle/product/19.0.0/dbhome_1/bin/oracle
$ readlink /proc/$PID/cwd      # current working directory
```

**Who started it: the parent chain**

```bash
$ pstree -aps $PID             # every parent up to systemd (PID 1), with arguments
$ ps -o pid,ppid,user,args -p $(ps -o ppid= -p $PID)    # just the parent
```

Typical results:

| Parent chain | Meaning |
|--------------|---------|
| `systemd → crond → sh → rman_backup.sh → rman` | a cron job |
| `systemd → sshd → bash → sqlplus` | someone ran it interactively over SSH |
| `systemd → postgres (postmaster) → postgres: app appdb ...` | a PostgreSQL client session |
| `systemd → oracle (LOCAL=NO)` | an Oracle dedicated server for a remote client |

**Which service, and which Oracle instance**

```bash
$ systemctl status $PID                                  # the systemd unit that owns the PID
$ cat /proc/$PID/cgroup                                  # the service or container it belongs to
$ tr '\0' '\n' < /proc/$PID/environ | grep -E 'ORACLE_SID|ORACLE_HOME|PGDATA'   # (same user or root)
```

**Which terminal / session and which client machine**

```bash
$ ps -o pid,sid,tty,user,args -p $PID      # tty '?' = no terminal (daemon, cron, DB server process)
$ ss -tnp | grep "pid=$PID,"               # TCP connections: shows the client IP:port
```

For an Oracle `(LOCAL=NO)` process or a PostgreSQL backend, the remote address from `ss` is the **application server** that sent the work.

---

## Step 5 — What is it doing? (OS view)

### 5a. State and threads

```bash
$ grep -E 'State|Threads|voluntary_ctxt' /proc/$PID/status
$ top -H -p $PID                             # CPU per THREAD inside the process
$ ps -L -o tid,pcpu,stat,comm -p $PID --sort=-pcpu | head    # same, as a snapshot
$ pidstat -t -p $PID 5 1                     # threads, current CPU
```

This matters for **MySQL** (one process, many threads, one thread per connection) and for Oracle with `threaded_execution=TRUE`. You need the **thread ID (TID)** to find the session.

### 5b. System calls: `strace`

```bash
# timeout 15 strace -c -f -p $PID       # 15 s summary: which system calls, how many, how long
# timeout 5 strace -tt -T -f -p $PID    # live list of calls with timestamps and durations
```

Reading it:

- **Almost no system calls, but 100% CPU** → it is computing in user space (SQL execution: joins, sorts, a bad plan, a loop). Go to Step 5c and Step 7.
- **Thousands of `read`/`pread64`/`lseek`** → heavy logical/physical reads.
- **Many `poll`/`epoll_wait`/`recvfrom`** → network chatter with the client (row-by-row fetching).
- **Many `futex`, `sched_yield` or `semop`** → threads fighting for locks/latches (high `%system`).

⚠️ `strace` slows the traced process down. Attach only for a few seconds (`timeout`) and never to a critical background process (such as `ora_lgwr`) during peak load.

### 5c. Where the CPU goes inside the code: `perf`

```bash
# perf top -p $PID                                   # live: functions using the most CPU
# perf record -F 99 -g -p $PID -- sleep 30           # record 30 s with call stacks
# perf report --stdio | head -60
```

Examples: Oracle `kcbgtcr` = consistent block reads (logical I/O); `qersoProcessULS`/`qesa...` = sorting and aggregation; PostgreSQL `ExecHashJoin`, `hash_search`, `slot_deform_heap_tuple` = executor work. You don't need to know every function. Oracle Support and PostgreSQL mailing lists can match them to known bugs.

### 5d. Stack snapshot (what it is doing right now)

```bash
# pstack $PID                                           # RHEL/OL (part of gdb)
# gdb -p $PID -batch -ex 'thread apply all bt' 2>/dev/null | head -60
# cat /proc/$PID/stack                                  # kernel stack (helpful for 'D' or high %system)
```

Take 3–5 snapshots a few seconds apart. The same functions every time show where it is stuck or spinning.

### 5e. Open files and I/O

```bash
$ lsof -p $PID | head -50           # datafiles, sockets, trace files
$ cat /proc/$PID/io                 # bytes read/written since start (run twice to see the rate)
$ pidstat -d -p $PID 5 1            # current disk I/O
$ pidstat -w -p $PID 5 1            # context switches per second (cswch/s, nvcswch/s)
```

---

## Step 6 — Kernel / system CPU (`sy` is high)

If `%system` is high rather than `%usr`:

```bash
$ LC_ALL=C pidstat -u 5 1 | awk '/^Average/ && $2 != "UID"' | sort -k5 -nr | head   # highest %system first
$ vmstat 2 5                                   # 'cs' (context switches) and 'in' (interrupts)
$ cat /sys/kernel/mm/transparent_hugepage/enabled   # THP 'always' → khugepaged / compaction CPU
$ grep -E 'HugePages_(Total|Free)' /proc/meminfo    # SGA without HugePages → page-table overhead
$ top -c -o %CPU                               # look for kswapd, khugepaged, ksoftirqd, kworker
```

| Kernel process busy | Likely cause |
|---------------------|--------------|
| `kswapd0` | memory shortage, see [04](04-memory-and-cpu.md) |
| `khugepaged`, `kcompactd` | Transparent HugePages, disable per [09](09-kernel-parameters-hugepages.md) |
| `ksoftirqd/N` | high network packet rate |
| many `futex`/`semop` in `strace` | lock/latch contention, too many active sessions |

---

## Step 7 — Map the OS process to the database session and SQL

This is the step that tells you the **database user, application and SQL** behind the PID.

### Oracle

```sql
-- Session and SQL for an OS PID (use v$process.stid instead of spid if threaded_execution=TRUE)
SELECT s.sid, s.serial#, s.username, s.osuser, s.machine, s.program, s.module,
       s.status, s.sql_id, s.event, s.last_call_et AS secs_in_call,
       SUBSTR(q.sql_text, 1, 200) AS sql_text
FROM   v$process p
JOIN   v$session s ON s.paddr = p.addr
LEFT JOIN v$sql q ON q.sql_id = s.sql_id AND q.child_number = s.sql_child_number
WHERE  p.spid = '&os_pid';

-- Full SQL text and plan
SELECT sql_fulltext FROM v$sql WHERE sql_id = '&sql_id' AND ROWNUM = 1;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('&sql_id', NULL, 'ALLSTATS LAST'));

-- Top CPU sessions right now, from inside the database
SELECT s.sid, s.username, s.program, s.sql_id, ROUND(st.value/100) AS cpu_secs
FROM   v$sesstat st JOIN v$statname n ON n.statistic# = st.statistic#
JOIN   v$session s ON s.sid = st.sid
WHERE  n.name = 'CPU used by this session' AND s.status = 'ACTIVE'
ORDER  BY st.value DESC FETCH FIRST 10 ROWS ONLY;
```

From the shell, in one go:

```bash
$ sqlplus -s / as sysdba <<EOF
set lines 200 pages 50
col username for a15
col program for a30
col sql_text for a80
SELECT s.sid, s.serial#, s.username, s.program, s.sql_id, SUBSTR(q.sql_text,1,80) sql_text
FROM v\$process p JOIN v\$session s ON s.paddr = p.addr
LEFT JOIN v\$sql q ON q.sql_id = s.sql_id AND q.child_number = s.sql_child_number
WHERE p.spid = '$PID';
EOF
```

If the PID is a **background** process (`ora_dbw0_`, `ora_lgwr_`, `ora_p000_`…), the name tells you the component. `ora_pNNN` are parallel query slaves: find their coordinator session in `v$px_session`.

### PostgreSQL

The process title already shows a lot: `postgres: <user> <database> <client_ip> <state>`.

```sql
SELECT pid, usename, datname, client_addr, application_name, backend_type,
       state, now() - query_start AS running_for, wait_event_type, wait_event,
       LEFT(query, 200) AS query
FROM   pg_stat_activity
WHERE  pid = <PID>;

-- All active queries, longest first
SELECT pid, usename, now() - query_start AS running_for, LEFT(query, 100)
FROM   pg_stat_activity
WHERE  state = 'active' AND pid <> pg_backend_pid()
ORDER  BY running_for DESC;
```

`backend_type` = `autovacuum worker`, `parallel worker`, `walsender`, … tells you when it is not a client query. For a parallel worker, `leader_pid` points to the session that started it (PG 13+).

### MySQL / MariaDB

MySQL is one `mysqld` process. Use `top -H -p $(pidof mysqld)` to find the busy **thread ID (TID)**, then:

```sql
-- MySQL 8.0
SELECT t.THREAD_OS_ID, t.PROCESSLIST_ID, t.PROCESSLIST_USER, t.PROCESSLIST_HOST,
       t.PROCESSLIST_DB, t.PROCESSLIST_COMMAND, t.PROCESSLIST_TIME,
       LEFT(t.PROCESSLIST_INFO, 200) AS query
FROM   performance_schema.threads t
WHERE  t.THREAD_OS_ID = <TID>;

-- All running statements, longest first
SELECT id, user, host, db, command, time, state, LEFT(info, 100) AS query
FROM   information_schema.processlist
WHERE  command <> 'Sleep' ORDER BY time DESC;
```

Background threads (`thread/innodb/page_cleaner_thread`, `purge` …) appear in `performance_schema.threads.NAME`.

---

## Step 8 — Take action (carefully)

First decide *what* it is: an expected batch job, a bad SQL plan, a runaway script, or a stuck process.

**Lower its priority instead of killing it**

```bash
# renice -n 10 -p $PID                       # lower CPU priority (19 = lowest)
# systemctl set-property --runtime <unit>.service CPUQuota=200%   # cap a service at 2 CPUs until reboot
```

**Stop the database work the proper way (preferred)**

```sql
-- Oracle
ALTER SYSTEM CANCEL SQL '<sid>, <serial#>';           -- 18c+: cancel only the statement
ALTER SYSTEM KILL SESSION '<sid>,<serial#>' IMMEDIATE;
-- PostgreSQL
SELECT pg_cancel_backend(<pid>);                        -- cancel query
SELECT pg_terminate_backend(<pid>);                     -- end session
-- MySQL
KILL QUERY <processlist_id>;
KILL <processlist_id>;
```

**OS kill: last resort**

```bash
$ kill $PID            # SIGTERM, gives it a chance to clean up
$ kill -9 $PID         # ⚠️ SIGKILL
```

⚠️ Never `kill -9` an Oracle background process (instance crash) or a PostgreSQL backend (the postmaster restarts **all** sessions). See [05 Process management](05-process-management.md#step-4--send-signals--kill).

---

## Step 9 — Catch a CPU spike that comes and goes

If the problem is over before you log in, collect evidence automatically.

**Look back with `sar` / `atop`**

```bash
$ sar -u -s 02:00:00 -e 03:00:00                       # CPU between 02:00 and 03:00 today
$ sar -u -f /var/log/sa/sa23                           # the 23rd of this month
$ sar -q -f /var/log/sa/sa23                           # run queue / load
# atop -r /var/log/atop/atop_$(date +%Y%m%d) -b 02:00   # per-PROCESS history (t = next sample, c = command)
```

**Record the top processes every 30 seconds** (run inside `tmux`/`nohup`):

```bash
$ nohup bash -c 'while true; do
    echo "===== $(date "+%F %T")"
    top -b -n 1 -c -o %CPU | head -20
    sleep 30
  done' >> /tmp/cpu_watch_$(hostname).log 2>&1 &
```

Stop it with `kill %1` (same shell) or `pkill -f cpu_watch`. Then search the log for the spike time:

```bash
$ grep -A20 '2026-09-24 02:1' /tmp/cpu_watch_$(hostname).log | less
```

Oracle-licensed shops (Diagnostics Pack) can also use **ASH/AWR** (`v$active_session_history`, `@?/rdbms/admin/ashrpt.sql`) to see the SQL behind a past CPU spike.

---

## Quick "who / what / doing" block for one PID

Copy, set `PID`, and paste into the terminal:

```bash
PID=48213
echo "--- who / command";   ps -o pid,ppid,user,%cpu,%mem,stat,lstart,etime,time,args -p $PID
echo "--- program";        readlink /proc/$PID/exe
echo "--- parent chain";   pstree -aps $PID
echo "--- state/threads";  grep -E 'State|Threads|ctxt' /proc/$PID/status
echo "--- current CPU";    pidstat -u -p $PID 3 1 | tail -2
echo "--- hottest threads"; ps -L -o tid,pcpu,stat,comm -p $PID --sort=-pcpu | head -6
echo "--- connections";    ss -tnp 2>/dev/null | grep "pid=$PID,"
```

Then run the database query from Step 7 with the same PID (or the thread ID for MySQL).

---

## Summary table

| Question | Commands |
|----------|----------|
| Is the CPU busy? | `uptime`, `vmstat 2 5`, `mpstat -P ALL 2`, `sar -u` |
| Which process? | `top -c -o %CPU`, `pidstat -u -U -l 5 1`, `ps -eo ... --sort=-%cpu`, `htop` |
| Which user? | `USER` column; per-user sums with `ps`/`pidstat` + `awk`; `top -u`; `w` |
| Which command? | `ps -fp`, `/proc/PID/cmdline`, `readlink /proc/PID/exe`, `pstree -aps`, `systemctl status PID`, `ss -tnp` |
| What is it doing? | `top -H -p`, `pidstat -t`, `strace -c`, `perf top`, `pstack`/`gdb`, `/proc/PID/io` |
| Which DB session / SQL? | Oracle `v$process.spid` → `v$session` → `v$sql`; PostgreSQL `pg_stat_activity`; MySQL `performance_schema.threads.THREAD_OS_ID` |
| What happened earlier? | `sar -f`, `atop -r`, a `top -b` logging loop, ASH/AWR |
