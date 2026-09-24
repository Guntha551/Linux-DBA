# 18 · Which Database Is Using the CPU?

**Goal:** On a server running several databases (Exadata, RAC, consolidated hosts), find **which database instance** uses the CPU, using only Linux commands. Then confirm it from inside the database and drill down to the PDB and SQL.

---

## Why "CPU per OS user" is not enough

Chapter [17](17-high-cpu-process-investigation.md#step-3--which-user-is-using-the-cpu) shows the total per OS user:

```
$ pidstat -u -U 5 1 | awk '/^Average/ && $2 != "USER" {cpu[$2]+=$8} END {for (u in cpu) printf "%-15s %6.1f\n", u, cpu[u]}' | sort -k2 -nr
grid            1619.4
oracle           397.9
root              64.0
```

- `pidstat` counts **100% as one full CPU**. `grid 1619.4` means the `grid` user is using about **16 CPUs**, and `oracle` about **4 CPUs**. Divide by `nproc` to get the share of the whole server.
- All databases usually run as the same OS user (`oracle`), so this cannot tell `ORCL` from `SALES`.
- The **`grid`** user owns much more than the clusterware: **ASM**, the **listeners**, the **MGMTDB**, and the **ASM processes that do work on behalf of each database**. A high `grid` number is therefore often *database* work in disguise.

The fix: Oracle puts the **instance name in every process name**, so you can add up CPU per instance.

---

## Step 1 — Learn to read Oracle process names

```bash
$ ps -eo user,pid,args | grep -E '[o]ra_pmon|[a]sm_pmon|[a]px_pmon|[m]db_pmon'   # one pmon per instance
```

| Process name (from `ps -ef` / `top -c`) | Owner | Belongs to |
|------------------------------------------|-------|-----------|
| `ora_pmon_ORCL1`, `ora_dbw0_ORCL1`, `ora_p001_ORCL1` | oracle | DB instance **ORCL1** (background / parallel slaves) |
| `oracleORCL1 (LOCAL=NO)` | oracle | DB instance **ORCL1**, a session from a remote client |
| `oracleORCL1 (DESCRIPTION=(LOCAL=YES)...)` | oracle | DB instance **ORCL1**, a local session (sqlplus / as sysdba, RMAN on the server) |
| `asm_pmon_+ASM1`, `asm_rbal_+ASM1`, `asm_arb0_+ASM1` | grid | **ASM** instance (rebalance = `arb`, `rbal`) |
| `oracle+ASM1_asmb_orcl1 (...)`, `oracle+ASM1_o000_orcl1` | grid | **ASM working for DB `orcl1`** (the suffix is the client DB instance) |
| `apx_pmon_+APX1` | grid | ASM proxy instance (ACFS / ADVM) |
| `mdb_pmon_-MGMTDB`, `oracle-MGMTDB` | grid | Grid Infrastructure Management Repository |
| `tnslsnr LISTENER -no_crs_notify -inherit` | grid | Listener **LISTENER** (SCAN listeners: `LISTENER_SCAN1` …) |
| `ocssd.bin`, `crsd.bin`, `ohasd.bin`, `oraagent.bin`, `gipcd.bin`, `evmd.bin`, `osysmond.bin`, `ologgerd`, `octssd.bin`, `diskmon.bin` | grid / root | **Grid Infrastructure** (clusterware) |
| `postgres: appuser appdb 10.0.0.21(51234) SELECT` | postgres | PostgreSQL database **appdb** |
| `mysqld --port=3307 ...` | mysql | MySQL instance on port **3307** |

---

## Step 2 — Quick view: CPU per instance with `pidstat` (one command)

Paste this as `root` (to see both `grid` and `oracle`). It takes a 5-second sample and adds up **current** CPU per instance:

```bash
pidstat -u -l 5 1 | awk '
  /^Average/ && /Command/ { for (i = 1; i <= NF; i++) { if ($i == "%CPU") c = i; if ($i == "Command") k = i }; next }
  /^Average/ && k {
      cmd = $k
      if      (cmd ~ /^(ora|asm|apx|mdb)_[a-z0-9]+_/) { db = cmd; sub(/^[a-z]+_[a-z0-9]+_/, "", db) }
      else if (cmd ~ /^oracle./)                     { db = substr(cmd, 7); sub(/_.*/, "", db) }
      else if (cmd ~ /tnslsnr$/)                     { db = "LISTENER" }
      else                                            { sub(/.*\//, "", cmd); db = "other:" cmd }
      cpu[db] += $c
  }
  END { for (d in cpu) printf "%-30s %8.1f\n", d, cpu[d] }' | sort -k2 -nr | head -20
```

Example output:

```
+ASM1                            1210.4
ORCL1                             352.0
SALES1                             41.5
other:ocssd.bin                    88.0
other:osysmond.bin                 35.2
LISTENER                           30.1
```

How it works:

- `pidstat -u -l` gives the **current** CPU of every process together with its full command line.
- The header line is used to find the `%CPU` and `Command` columns, so it works with every sysstat version.
- `ora_xxxx_ORCL1` → `ORCL1`, `oracleORCL1` → `ORCL1`, `asm_xxxx_+ASM1` / `oracle+ASM1_…` → `+ASM1`, everything else is grouped by program name.

---

## Step 3 — Detailed view: the `cpu_by_database.sh` script

[`scripts/cpu_by_database.sh`](../scripts/cpu_by_database.sh) does the same with more detail and fewer requirements. It reads `/proc` directly, needs no `sysstat`, and runs on bash 4.2+ (OL7 / RHEL7 and later).

```bash
# ./cpu_by_database.sh            # 5-second sample
# ./cpu_by_database.sh 10 -v      # 10-second sample + the 20 busiest processes
```

```
CPU by database on exadb01 - 5s sample at 2026-09-24 10:15:02
CPUs: 48 (100% = one CPU, server maximum = 4800%)

GROUP                                             %CPU   %SERVER
-----                                             ----   -------
Oracle ASM    +ASM1 (for orcl1)                  1105.2     23.0%
Oracle DB     ORCL1                               352.0      7.3%
Oracle ASM    +ASM1                               105.2      2.2%
Other         [grid] ocssd.bin                     88.0      1.8%
Oracle DB     SALES1                               41.5      0.9%
Listener      LISTENER                             30.1      0.6%
...
```

What it adds compared with Step 2:

- **ASM work is attributed to the database it serves** (`+ASM1 (for orcl1)`), so you can see which database is causing ASM CPU.
- Separate groups for APX, MGMTDB, each listener, each PostgreSQL database and each MySQL port.
- Non-database processes appear as `[user] program`, e.g. `[grid] ocssd.bin`.
- The `%SERVER` column shows the share of the whole machine.

---

## Step 4 — Drill into the busiest instance

Once you know the instance (for example `ORCL1`), list only its processes:

```bash
# All processes of ORCL1, busiest first (current CPU)
$ pidstat -u -l -p $(pgrep -d, -f '^(ora_[a-z0-9]+_ORCL1|oracleORCL1)( |$)') 5 1 | grep '^Average' | sort -k8 -nr | head -20
#   (%CPU is column 8 on sysstat 11.5+; use -k7 on older versions)

# Live, in top (top accepts up to 20 PIDs)
$ top -c -p $(pgrep -f '^(ora_[a-z0-9]+_ORCL1|oracleORCL1)( |$)' | head -20 | paste -sd,)

# How many sessions does each instance have right now?
$ ps -eo args | grep -oE '^oracle[A-Za-z0-9_+-]+' | sort | uniq -c | sort -nr
```

Then look at the result:

- **Mostly `oracleORCL1 (LOCAL=NO)`** → user sessions / SQL. Map the top PIDs to SQL with the query in [17 · Step 7](17-high-cpu-process-investigation.md#step-7--map-the-os-process-to-the-database-session-and-sql).
- **Many `ora_pNNN_ORCL1`** → parallel query. Find the coordinator in `v$px_session`.
- **`ora_j0NN_` / `ora_m0NN_`** → scheduler jobs / manageability (stats gathering, AWR, advisors).
- **`ora_dbw*`, `ora_lgwr`** → heavy DML / redo activity.

---

## Step 5 — If `grid` is the top user

Show only `grid`'s processes, busiest first:

```bash
# top -b -d 5 -n 2 -c -u grid -o %CPU | awk '/^top -/{n++} n==2' | head -30
```

| Busy process | Usual reason | Check |
|--------------|--------------|-------|
| `oracle+ASM1_…_<dbsid>` | ASM doing work for that database (file creation/extension, heavy metadata or I/O calls) | Which `<dbsid>` suffix dominates → look at that database's activity |
| `asm_arb*`, `asm_rbal`, `asm_x0*` | **ASM rebalance** after a disk add/drop/failure | `SELECT * FROM gv$asm_operation;` in the ASM instance |
| `tnslsnr` | **Logon storm**: an application opening thousands of connections | Connections per minute in `listener.log`; use connection pooling |
| `ocssd.bin`, `gipcd.bin`, `octssd.bin` | Clusterware heartbeats, interconnect problems, time sync | `crsctl stat res -t -init`, the CRS alert log, `chronyc tracking` |
| `osysmond.bin`, `ologgerd`, `mdb_*_-MGMTDB`, a `java` process for Cluster Health Advisor | Cluster Health Monitor / Advisor / MGMTDB | `crsctl stat res ora.crf -init`, `chactl status`. Check with Oracle Support before disabling |
| `oraagent.bin`, `orarootagent.bin` | Clusterware agents checking many resources (often many services/databases) | Agent logs under `$ORACLE_BASE/diag/crs/<host>/crs/trace` |
| `diskmon.bin` (Exadata) | Communication with storage cells | CRS alert log, `cellcli` on the cells |

In the example at the top of this page (`grid` ≈ 16 CPUs, `oracle` ≈ 4 CPUs), the script from Step 3 shows at once whether those 16 CPUs are ASM rebalance, ASM work for one database, a listener logon storm, or the clusterware itself.

---

## Step 6 — Confirm from inside each database

The OS view shows **where** the CPU goes. The database confirms it and tells you **which PDB and SQL**.

### CPU used by every running instance (loop from Linux)

Run as `oracle`. It finds each running instance and its `ORACLE_HOME` from the pmon process, so `/etc/oratab` is not needed:

```bash
for pmon in $(pgrep -f '^ora_pmon_'); do
    sid=$(ps -o args= -p "$pmon"); sid=${sid#ora_pmon_}; sid=${sid%% *}
    home=$(dirname "$(dirname "$(readlink /proc/$pmon/exe)")")
    ORACLE_SID=$sid ORACLE_HOME=$home "$home/bin/sqlplus" -s / as sysdba <<'EOF'
set head off feed off pages 0 lines 200
SELECT RPAD(i.instance_name, 16) || ' DB CPU: ' || TO_CHAR(ROUND(m.value / 100, 2), '990.00') || ' CPUs'
FROM   v$instance i, v$sysmetric m
WHERE  m.metric_name = 'CPU Usage Per Sec' AND m.group_id = 2;
EOF
done
```

`CPU Usage Per Sec` is in centiseconds per second over the last 60 seconds, so `/100` = number of CPUs used by that instance.

### RAC: all instances of a database in one query

```sql
SELECT inst_id, ROUND(value / 100, 2) AS cpus_used
FROM   gv$sysmetric
WHERE  metric_name = 'CPU Usage Per Sec' AND group_id = 2
ORDER  BY inst_id;
```

### Multitenant: which PDB inside the CDB?

The OS **cannot see PDBs**: all PDBs share the CDB's processes. Ask the CDB (12.2+):

```sql
-- CPU per PDB, last 60 seconds
SELECT p.name AS pdb, ROUND(m.value / 100, 2) AS cpus_used
FROM   v$con_sysmetric m JOIN v$pdbs p ON p.con_id = m.con_id
WHERE  m.metric_name = 'CPU Usage Per Sec'
ORDER  BY m.value DESC;

-- Active sessions on CPU right now, per PDB
SELECT NVL(p.name, 'CDB$ROOT') AS pdb, COUNT(*) AS sessions_on_cpu
FROM   v$session s LEFT JOIN v$pdbs p ON p.con_id = s.con_id
WHERE  s.status = 'ACTIVE' AND s.state <> 'WAITING' AND s.type = 'USER'
GROUP  BY p.name ORDER BY 2 DESC;
```

With the Diagnostics Pack licence, ASH gives the history (which PDB and SQL used CPU in the last hour):

```sql
SELECT p.name AS pdb, h.sql_id, COUNT(*) AS cpu_samples   -- 1 sample ≈ 1 second on CPU
FROM   v$active_session_history h LEFT JOIN v$pdbs p ON p.con_id = h.con_id
WHERE  h.session_state = 'ON CPU' AND h.sample_time > SYSDATE - 1/24
GROUP  BY p.name, h.sql_id ORDER BY cpu_samples DESC FETCH FIRST 15 ROWS ONLY;
```

### PostgreSQL and MySQL

- **PostgreSQL:** each backend's process title contains the database name, and Steps 2–3 already group by it. Confirm with `SELECT datname, count(*) FROM pg_stat_activity WHERE state = 'active' GROUP BY 1;`. With several clusters on one host, set `cluster_name` in `postgresql.conf` so the titles show which cluster each process belongs to.
- **MySQL:** one `mysqld` per instance. The script groups by `--port`. Inside an instance, see [17 · Step 7](17-high-cpu-process-investigation.md#mysql--mariadb).

---

## Step 7 — Watch it over time

```bash
# Every 60 s, append the per-database breakdown to a log (run in tmux or with nohup)
$ nohup bash -c 'while true; do /opt/Linux-DBA/scripts/cpu_by_database.sh 10; echo; sleep 50; done' \
      >> /tmp/cpu_by_db_$(hostname).log 2>&1 &
```

Or add a cron entry (see [11](11-scheduling-cron-systemd.md)):

```cron
*/5 * * * * /opt/Linux-DBA/scripts/cpu_by_database.sh 10 >> /var/log/cpu_by_db.log 2>&1
```

For long-term history per database, use AWR (`@?/rdbms/admin/awrrpt.sql`, Load Profile → *DB CPU*), Enterprise Manager, or Exadata's ExaWatcher data.

---

## Summary

| Question | How |
|----------|-----|
| Which OS user? | `pidstat -u -U 5 1` + sum per user (chapter 17) |
| Which **instance**? | Step 2 one-liner or `scripts/cpu_by_database.sh` (groups by the SID in the process name) |
| Is ASM work caused by a database? | Script groups `oracle+ASM1_…_<dbsid>` as `+ASM1 (for <dbsid>)` |
| Why is `grid` busy? | `top -u grid`, then the table in Step 5 |
| Which processes inside the instance? | `pgrep -f '^(ora_[a-z0-9]+_ORCL1\|oracleORCL1)( \|$)'` + `pidstat -p` / `top -p` |
| Which **PDB**? | `v$con_sysmetric`, `v$session` per `con_id`, ASH |
| Which **SQL**? | PID → `v$process.spid` → `v$session.sql_id` (chapter 17, Step 7) |
