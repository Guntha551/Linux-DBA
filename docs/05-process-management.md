# 05 · Process Management

**Goal:** Find database processes, understand their state, and stop them safely when needed.

---

## Step 1 — List database processes

```bash
$ ps -ef | grep pmon | grep -v grep       # Oracle: one ora_pmon_<SID> per running instance
$ ps -ef | grep tnslsnr                    # Oracle listener
$ ps -ef | grep -E 'postgres|postmaster'   # PostgreSQL
$ ps -ef | grep mysqld                     # MySQL / MariaDB
$ pgrep -a -u postgres                     # all processes owned by a user, with command line
$ pstree -p $(pgrep -o postgres)           # PostgreSQL process tree under the postmaster
```

Output columns of `ps -ef`: `UID PID PPID C STIME TTY TIME CMD`. `PPID` (parent PID) lets you see which child belongs to which instance.

---

## Step 2 — Process state

```bash
$ ps -eo pid,stat,wchan:30,cmd | grep -E ' D| Z'
```

| STAT | Meaning |
|------|---------|
| `R` | running |
| `S` | sleeping (normal idle) |
| `D` | uninterruptible sleep — **usually waiting on disk/NFS**; cannot be killed |
| `Z` | zombie — finished, parent has not collected it |
| `T` | stopped |

Many processes in `D` state = storage problem, not a database problem.

---

## Step 3 — Details for one process

```bash
$ ls -l /proc/<PID>/cwd            # working directory
$ cat /proc/<PID>/cmdline | tr '\0' ' '
$ cat /proc/<PID>/environ | tr '\0' '\n' | grep ORACLE_SID   # which instance does this belong to?
$ cat /proc/<PID>/limits            # effective ulimits (open files, processes)
$ ls /proc/<PID>/fd | wc -l         # number of open file descriptors
$ lsof -p <PID>                     # open files and sockets
```

---

## Step 4 — Send signals / kill

```bash
$ kill <PID>          # SIGTERM (15) — polite, lets the process clean up
$ kill -9 <PID>       # ⚠️ SIGKILL — immediate, no cleanup
$ pkill -f 'sqlplus.*batch_job'   # kill by command-line pattern
```

**⚠️ Database-specific rules:**

- **Oracle:** Kill only *dedicated server* processes (`oracle<SID> (LOCAL=NO)`). Killing a background process (`ora_pmon`, `ora_smon`, `ora_lgwr`, `ora_dbw0` …) **crashes the instance**. Prefer `ALTER SYSTEM KILL SESSION 'sid,serial#' IMMEDIATE;`.
  ```bash
  $ ps -ef | grep 'LOCAL=NO' | grep -v grep
  ```
- **PostgreSQL:** Never `kill -9` a backend — the postmaster will restart **all** sessions to protect shared memory. Use SQL:
  ```sql
  SELECT pg_cancel_backend(<pid>);     -- cancel the query
  SELECT pg_terminate_backend(<pid>);  -- end the session
  ```
- **MySQL:** Use `KILL QUERY <id>;` or `KILL <id>;` from the client.

---

## Step 5 — Run long jobs so they survive logout

```bash
$ nohup expdp system/**** parfile=exp.par > exp.log 2>&1 &
$ jobs; fg %1; bg %1         # manage background jobs in the current shell
$ disown -h %1                # detach an already-running job from the terminal

$ tmux new -s upgrade         # persistent terminal session (recommended)
#  Ctrl-b d                   -> detach
$ tmux attach -t upgrade      # reattach later, even from a new SSH connection
$ screen -S upgrade / screen -r upgrade   # alternative to tmux
```

**Always** run upgrades, imports and long RMAN jobs inside `tmux`/`screen` — a dropped VPN will otherwise kill them.

---

## Step 6 — Priority

```bash
$ nice -n 10 gzip -9 big_dump.dmp       # start with lower priority
# renice -n 15 -p <PID>                 # lower priority of a running process
# ionice -c3 -p <PID>                   # idle I/O class — backup won't starve the DB
```

---

## Step 7 — Trace what a process is doing

```bash
# strace -p <PID> -f -tt -o /tmp/trace.txt     # system calls (use briefly — adds overhead)
# pstack <PID>        # or: gdb -p <PID> -batch -ex 'thread apply all bt'  -- stack of a hung process
$ cat /proc/<PID>/stack                         # kernel stack (for D-state processes)
```

---

## Step 8 — Services with systemd

```bash
# systemctl status postgresql-16
# systemctl start|stop|restart mysqld
# systemctl enable --now postgresql-16          # start now and at boot
# systemctl list-units --type=service | grep -i -E 'ora|postgres|mysql'
# journalctl -u postgresql-16 --since "1 hour ago"
```
