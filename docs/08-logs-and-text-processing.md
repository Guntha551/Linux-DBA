# 08 · Logs & Text Processing

**Goal:** Find errors fast in alert logs, PostgreSQL/MySQL logs and system logs, and manage log growth.

---

## Where the logs are

| Component | Default location |
|-----------|------------------|
| Oracle alert log | `$ORACLE_BASE/diag/rdbms/<db>/<SID>/trace/alert_<SID>.log` |
| Oracle listener | `$ORACLE_BASE/diag/tnslsnr/<host>/listener/trace/listener.log` |
| PostgreSQL (RHEL) | `/var/lib/pgsql/<ver>/data/log/` |
| PostgreSQL (Ubuntu) | `/var/log/postgresql/` |
| MySQL | `/var/log/mysqld.log` or `/var/log/mysql/error.log` |
| OS messages | `/var/log/messages` (RHEL) / `/var/log/syslog` (Ubuntu) / `journalctl` |

Find the Oracle alert log quickly:

```bash
$ adrci exec="show alert -tail 50"
$ find $ORACLE_BASE/diag -name "alert_*.log"
```

---

## Step 1 — Viewing files

```bash
$ tail -100 alert_ORCL.log         # last 100 lines
$ tail -f alert_ORCL.log           # follow live (Ctrl-C to stop)
$ tail -F postgresql.log           # follow even if the file is rotated
$ less +G alert_ORCL.log           # open at the end; '/ORA-' searches, 'n' next, '?' backwards
$ head -50 file                    # first 50 lines
```

---

## Step 2 — Searching with grep

```bash
$ grep 'ORA-' alert_ORCL.log                        # all Oracle errors
$ grep -n 'ORA-00600' alert_ORCL.log                # with line numbers
$ grep -B5 -A10 'ORA-00600' alert_ORCL.log          # 5 lines before, 10 after (context)
$ grep -i -E 'error|fatal|panic' postgresql-*.log   # case-insensitive, several patterns
$ grep -c 'deadlock' postgresql.log                 # count matches
$ grep -rl 'ORA-01555' $ORACLE_BASE/diag            # which files contain it
$ grep -v '^#' postgresql.conf | grep -v '^\s*$'    # config without comments and blank lines
$ zgrep 'ERROR' mysqld.log-2026*.gz                 # grep inside compressed logs
```

---

## Step 3 — Summarising with awk / sort / uniq

```bash
# count each ORA- error, most frequent first
$ grep -o 'ORA-[0-9]\{5\}' alert_ORCL.log | sort | uniq -c | sort -nr

# PostgreSQL: count errors by type
$ grep -h 'ERROR:' /var/lib/pgsql/16/data/log/*.log | awk -F'ERROR:' '{print $2}' | sort | uniq -c | sort -nr | head

# failed logins per client IP in the listener log
$ grep 'establish' listener.log | grep -o 'HOST=[0-9.]*' | sort | uniq -c | sort -nr | head
```

`awk` basics: `$1`, `$2` … are fields, `-F` sets the separator, `NR` is the line number.

```bash
$ df -h | awk 'NR>1 && $5+0 > 80 {print $6, $5}'   # filesystems above 80%
```

---

## Step 4 — Logs for a time window

```bash
# Oracle alert log lines between two timestamps (ISO format, 12c+)
$ sed -n '/2026-09-24T02:00/,/2026-09-24T03:00/p' alert_ORCL.log

# journalctl
# journalctl --since "2026-09-24 02:00" --until "2026-09-24 03:00"
# journalctl -p err -b              # errors since the last boot
# journalctl -u mysqld -f           # follow one service
```

---

## Step 5 — Editing text with sed

```bash
$ sed -n '100,150p' file                          # print lines 100–150
$ sed 's/old_host/new_host/g' tnsnames.ora        # preview a replacement
$ sed -i.bak 's/old_host/new_host/g' tnsnames.ora # ⚠️ edit in place, keep a .bak copy
$ sed -i 's/^#\?max_connections.*/max_connections = 300/' postgresql.conf
```

---

## Step 6 — Comparing files

```bash
$ diff init_old.ora init_new.ora
$ diff -y --suppress-common-lines a.conf b.conf   # side by side, differences only
$ sdiff postgresql.conf.bak postgresql.conf
$ md5sum file1 file2                               # identical files? (e.g. after copying a backup)
```

---

## Step 7 — Log rotation

```bash
$ cat /etc/logrotate.d/postgresql
# logrotate -d /etc/logrotate.d/oracle-alert       # dry run
```

Example `/etc/logrotate.d/oracle-alert`:

```
/u01/app/oracle/diag/rdbms/*/*/trace/alert_*.log
/u01/app/oracle/diag/tnslsnr/*/listener/trace/listener.log {
    weekly
    rotate 8
    compress
    copytruncate      # the database keeps the file open — copy, then truncate in place
    missingok
    notifempty
}
```

Oracle ADR can also purge its own files:

```bash
$ adrci exec="set home diag/rdbms/orcl/ORCL; purge -age 10080 -type TRACE"   # older than 7 days (minutes)
```
