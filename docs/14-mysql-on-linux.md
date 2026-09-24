# 14 · MySQL / MariaDB on Linux

**Goal:** Install, locate, start/stop, back up and troubleshoot MySQL from the OS side.

---

## Step 1 — Install

```bash
# dnf install -y mysql-server          # RHEL 8/9 (AppStream MySQL 8.0)
# systemctl enable --now mysqld
# grep 'temporary password' /var/log/mysqld.log     # only for Oracle's MySQL community RPMs
# mysql_secure_installation            # set root password, remove test DB and anonymous users

# apt install -y mysql-server           # Ubuntu (service name: mysql)
# apt install -y mariadb-server         # MariaDB (service name: mariadb)
```

---

## Step 2 — Find configuration and data

```bash
$ mysqld --verbose --help | grep -A1 'Default options'   # order in which my.cnf files are read
$ mysql -e "SELECT @@datadir, @@socket, @@port, @@log_error;"
$ ls /etc/my.cnf /etc/my.cnf.d/ /etc/mysql/ 2>/dev/null
$ sudo du -sh /var/lib/mysql/*                            # size per database
```

Store credentials so scripts don't expose passwords on the command line:

```bash
$ cat > ~/.my.cnf <<'EOF'
[client]
user=dbadmin
password=Secret123
EOF
$ chmod 600 ~/.my.cnf
# or, safer (obfuscated):  mysql_config_editor set --login-path=admin --user=dbadmin --password
```

---

## Step 3 — Start / stop / status

```bash
# systemctl start|stop|restart|status mysqld        # 'mysql' on Ubuntu, 'mariadb' for MariaDB
$ mysqladmin status
$ mysqladmin -u root -p processlist
$ mysqladmin -u root -p shutdown
$ mysqladmin ping
```

---

## Step 4 — Connect

```bash
$ mysql -u root -p
$ mysql -h dbhost01 -P 3306 -u app -p appdb
$ mysql -e "SHOW DATABASES;"                     # one-shot query from the shell
$ mysql -N -B -e "SELECT COUNT(*) FROM appdb.orders;"   # no headers, tab-separated (for scripts)
```

---

## Step 5 — Allow remote connections

```bash
$ grep -r bind-address /etc/my.cnf* /etc/mysql/
bind-address = 0.0.0.0
# systemctl restart mysqld
# firewall-cmd --permanent --add-service=mysql && firewall-cmd --reload
```

```sql
CREATE USER 'app'@'10.0.0.%' IDENTIFIED BY 'StrongPass!';
GRANT SELECT, INSERT, UPDATE, DELETE ON appdb.* TO 'app'@'10.0.0.%';
```

---

## Step 6 — Backup and restore

```bash
# logical backup, consistent for InnoDB without locking tables
$ mysqldump --single-transaction --routines --triggers --events --source-data=2 appdb | gzip > appdb_$(date +%F).sql.gz
$ mysqldump --single-transaction --all-databases > all_$(date +%F).sql
# (MySQL < 8.0.26 / MariaDB: use --master-data=2 instead of --source-data=2)

# restore
$ gunzip -c appdb_2026-09-24.sql.gz | mysql appdb

# faster parallel logical backup (MySQL Shell)
$ mysqlsh -- util dump-instance /backup/dump_$(date +%F) --threads=8

# physical hot backup (Percona XtraBackup)
$ xtrabackup --backup --target-dir=/backup/xb_$(date +%F)
$ xtrabackup --prepare --target-dir=/backup/xb_2026-09-24
```

---

## Step 7 — Binary logs and disk space

```bash
$ ls -lh /var/lib/mysql/binlog.* | tail
$ du -ch /var/lib/mysql/binlog.* | tail -1
```

**⚠️ Never `rm` binlogs by hand** — use SQL so the index file stays correct:

```sql
SHOW BINARY LOGS;
PURGE BINARY LOGS BEFORE NOW() - INTERVAL 3 DAY;
SET PERSIST binlog_expire_logs_seconds = 604800;   -- auto-purge after 7 days
```

---

## Step 8 — Replication status

```bash
$ mysql -e "SHOW REPLICA STATUS\G" | grep -E 'Running|Seconds_Behind|Last_.*Error'   # 8.0.22+
$ mysql -e "SHOW SLAVE STATUS\G"   # older versions / MariaDB
```

`Replica_IO_Running: Yes` and `Replica_SQL_Running: Yes` with a low `Seconds_Behind_Source` = healthy.

---

## Step 9 — Logs and troubleshooting

```bash
$ tail -100 /var/log/mysqld.log               # error log (path from @@log_error)
$ grep -i -E 'error|crash|innodb' /var/log/mysqld.log | tail
$ mysql -e "SHOW ENGINE INNODB STATUS\G" | less   # deadlocks, buffer pool, I/O
$ mysql -e "SHOW FULL PROCESSLIST;"
$ mysqldumpslow -s t -t 10 /var/lib/mysql/*-slow.log   # top 10 slow queries by total time
```

---

## Step 10 — Check and repair tables

```bash
$ mysqlcheck -u root -p --all-databases --check
$ mysqlcheck -u root -p --optimize appdb       # ⚠️ rebuilds tables — locks/IO heavy
$ mysqlcheck -u root -p --auto-repair appdb    # MyISAM/Aria only
```
