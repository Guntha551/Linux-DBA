# 11 · Scheduling: cron, at & systemd timers

**Goal:** Automate backups, statistics gathering and housekeeping.

---

## Step 1 — Manage your crontab

```bash
$ crontab -l            # list jobs for the current user
$ crontab -e            # edit
# crontab -l -u oracle  # root: view another user's crontab
$ crontab -l > ~/crontab_backup_$(date +%F).txt    # back it up before editing!
```

**⚠️** `crontab -r` deletes the whole crontab without asking. It is one key away from `-e`.

---

## Step 2 — Crontab syntax

```
┌──────── minute (0-59)
│ ┌────── hour (0-23)
│ │ ┌──── day of month (1-31)
│ │ │ ┌── month (1-12)
│ │ │ │ ┌ day of week (0-7, 0 and 7 = Sunday)
│ │ │ │ │
* * * * *  command
```

| Example | Meaning |
|---------|---------|
| `0 2 * * *` | every day 02:00 |
| `30 1 * * 0` | Sundays 01:30 |
| `*/15 * * * *` | every 15 minutes |
| `0 */4 * * *` | every 4 hours |
| `0 22 * * 1-5` | weekdays at 22:00 |
| `0 3 1 * *` | 1st of each month 03:00 |

---

## Step 3 — Real DBA crontab

```cron
# Environment: cron does NOT read .bash_profile
SHELL=/bin/bash
MAILTO=dba-team@example.com

# Oracle: daily level-1 RMAN backup at 01:00
0 1 * * *    . /home/oracle/.bash_profile; /home/oracle/scripts/rman_l1.sh >> /home/oracle/logs/rman_l1_$(date +\%F).log 2>&1

# Oracle: archive log backup every 2 hours
0 */2 * * *  . /home/oracle/.bash_profile; /home/oracle/scripts/rman_arch.sh > /dev/null 2>&1

# PostgreSQL: nightly logical dump (as postgres)
30 0 * * *   pg_dump -Fc mydb > /backup/pg/mydb_$(date +\%F).dump 2>> /backup/pg/dump_errors.log

# Housekeeping: remove trace files older than 7 days
0 5 * * *    find /u01/app/oracle/diag -name "*.tr[cm]" -mtime +7 -delete

# Disk space check every 30 minutes
*/30 * * * * /opt/Linux-DBA/scripts/disk_space_alert.sh 85
```

**Key points**

1. `%` is special in crontab — escape it as `\%`.
2. Source the profile (`. ~/.bash_profile`) or set `ORACLE_HOME`, `ORACLE_SID`, `PATH` explicitly.
3. Always redirect output (`>> log 2>&1`), otherwise cron mails it or loses it.
4. Use absolute paths.

---

## Step 4 — Check whether cron ran

```bash
# grep CROND /var/log/cron | tail           # RHEL
# grep CRON /var/log/syslog | tail          # Ubuntu
# journalctl -u crond --since today
# systemctl status crond                    # 'cron' on Ubuntu
```

---

## Step 5 — Prevent overlapping runs

```bash
*/10 * * * * flock -n /tmp/arch_backup.lock /home/oracle/scripts/rman_arch.sh
```

`flock -n` exits immediately if the previous run still holds the lock.

---

## Step 6 — One-off jobs with at

```bash
$ echo "/home/oracle/scripts/gather_stats.sh" | at 23:30
$ at now + 2 hours < job.sh
$ atq            # list pending jobs
$ atrm <job#>    # remove
```

---

## Step 7 — systemd timers (modern alternative)

`/etc/systemd/system/pg-backup.service`

```ini
[Unit]
Description=Nightly PostgreSQL backup

[Service]
Type=oneshot
User=postgres
ExecStart=/usr/local/bin/pg_backup.sh
```

`/etc/systemd/system/pg-backup.timer`

```ini
[Unit]
Description=Run pg-backup nightly

[Timer]
OnCalendar=*-*-* 00:30:00
Persistent=true          # run at boot if the server was down at 00:30

[Install]
WantedBy=timers.target
```

```bash
# systemctl daemon-reload
# systemctl enable --now pg-backup.timer
$ systemctl list-timers
$ journalctl -u pg-backup.service       # full log of every run
```

---

## Step 8 — Start the database automatically at boot (Oracle)

`/etc/systemd/system/dbora.service`

```ini
[Unit]
Description=Oracle Database and Listener
After=network-online.target

[Service]
Type=forking
User=oracle
Group=oinstall
Environment=ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
ExecStart=/u01/app/oracle/product/19.0.0/dbhome_1/bin/dbstart /u01/app/oracle/product/19.0.0/dbhome_1
ExecStop=/u01/app/oracle/product/19.0.0/dbhome_1/bin/dbshut  /u01/app/oracle/product/19.0.0/dbhome_1
RemainAfterExit=yes
TimeoutStopSec=600
LimitMEMLOCK=infinity
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

Set the instance flag to `Y` in `/etc/oratab` (`ORCL:/u01/app/oracle/product/19.0.0/dbhome_1:Y`), then `systemctl enable dbora`.
