# 13 · PostgreSQL on Linux

**Goal:** Install, locate, start/stop and maintain PostgreSQL from the OS side.

Paths below use PostgreSQL 16 on RHEL (`/var/lib/pgsql/16/data`). On Ubuntu: data in `/var/lib/postgresql/16/main`, config in `/etc/postgresql/16/main`.

---

## Step 1 — Install (RHEL family, PGDG repository)

```bash
# dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
# dnf -qy module disable postgresql
# dnf install -y postgresql16-server postgresql16-contrib
# /usr/pgsql-16/bin/postgresql-16-setup initdb
# systemctl enable --now postgresql-16
```

Ubuntu: `# apt install -y postgresql` (cluster is created and started automatically).

---

## Step 2 — Find the data directory and config files

```bash
$ sudo -u postgres psql -c "SHOW data_directory;"
$ sudo -u postgres psql -c "SHOW config_file;"
$ sudo -u postgres psql -c "SHOW hba_file;"
$ ps -ef | grep [p]ostgres | grep -- -D           # data dir from the postmaster command line
$ pg_lsclusters                                  # Ubuntu only: all clusters, ports, status
```

---

## Step 3 — Start / stop / reload

```bash
# systemctl start|stop|restart|status postgresql-16
# systemctl reload postgresql-16         # re-read postgresql.conf / pg_hba.conf, no downtime

$ pg_ctl -D /var/lib/pgsql/16/data status
$ pg_ctl -D /var/lib/pgsql/16/data stop -m fast       # fast = disconnect clients, clean shutdown
$ pg_ctl -D /var/lib/pgsql/16/data reload
$ psql -c "SELECT pg_reload_conf();"
```

Shutdown modes: `smart` (wait for clients), `fast` (recommended), `immediate` (⚠️ crash-like, recovery on next start).

---

## Step 4 — Connect

```bash
$ sudo -iu postgres
$ psql                                # local socket, peer authentication
$ psql -h dbhost01 -p 5432 -U appuser -d appdb
$ pg_isready -h dbhost01              # accepting connections?
```

Useful `psql` meta-commands: `\l` databases, `\dt` tables, `\du` roles, `\x` expanded output, `\timing`, `\q` quit.

Password file for scripts:

```bash
$ echo "dbhost01:5432:appdb:appuser:Secret123" >> ~/.pgpass && chmod 600 ~/.pgpass
```

---

## Step 5 — Allow remote connections

```bash
$ vi /var/lib/pgsql/16/data/postgresql.conf
listen_addresses = '*'

$ vi /var/lib/pgsql/16/data/pg_hba.conf
# TYPE  DATABASE  USER     ADDRESS        METHOD
host    appdb     appuser  10.0.0.0/24    scram-sha-256

# systemctl restart postgresql-16          # listen_addresses needs a restart; pg_hba only a reload
# firewall-cmd --permanent --add-service=postgresql && firewall-cmd --reload
```

---

## Step 6 — Backup and restore

```bash
$ pg_dump -Fc -d appdb -f /backup/appdb_$(date +%F).dump        # custom format, compressed
$ pg_dump -Fd -j 4 -d appdb -f /backup/appdb_dir                 # directory format, 4 parallel jobs
$ pg_dumpall --globals-only > /backup/globals.sql                # roles and tablespaces
$ pg_restore -l appdb.dump | head                                # list contents
$ pg_restore -d appdb_new -j 4 /backup/appdb_2026-09-24.dump     # restore in parallel
$ pg_basebackup -D /backup/base_$(date +%F) -Ft -z -P -X stream  # physical backup (for PITR / replicas)
```

---

## Step 7 — WAL and disk space

```bash
$ du -sh /var/lib/pgsql/16/data/pg_wal
$ ls /var/lib/pgsql/16/data/pg_wal | wc -l
```

`pg_wal` grows when: archiving fails (`archive_command`), a replication slot is inactive, or `max_wal_size` is large. **⚠️ Never delete files in `pg_wal` manually** — the cluster will not start. Diagnose instead:

```sql
SELECT * FROM pg_stat_archiver;
SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained FROM pg_replication_slots;
```

---

## Step 8 — Replication status

```bash
$ psql -x -c "SELECT client_addr, state, sync_state, write_lag, replay_lag FROM pg_stat_replication;"   # on primary
$ psql -c "SELECT pg_is_in_recovery(), now() - pg_last_xact_replay_timestamp() AS lag;"                 # on standby
```

---

## Step 9 — Logs

```bash
$ ls -ltr /var/lib/pgsql/16/data/log/
$ tail -f /var/lib/pgsql/16/data/log/postgresql-$(date +%a).log
$ grep -E 'FATAL|PANIC|ERROR' /var/lib/pgsql/16/data/log/*.log | tail -50
```

---

## Step 10 — Upgrade a major version (pg_upgrade)

```bash
# dnf install -y postgresql17-server
# /usr/pgsql-17/bin/postgresql-17-setup initdb
# systemctl stop postgresql-16
$ /usr/pgsql-17/bin/pg_upgrade \
    -b /usr/pgsql-16/bin -B /usr/pgsql-17/bin \
    -d /var/lib/pgsql/16/data -D /var/lib/pgsql/17/data --check    # dry run first
$ # rerun without --check (add --link for fast in-place upgrade)
# systemctl enable --now postgresql-17
$ /usr/pgsql-17/bin/vacuumdb --all --analyze-in-stages
```
