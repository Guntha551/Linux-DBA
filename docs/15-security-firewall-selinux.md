# 15 · Security, Firewall & SELinux

**Goal:** Open database ports safely, keep SELinux from blocking the database, and harden SSH access.

---

## Step 1 — firewalld (RHEL / OL / Rocky)

```bash
# systemctl status firewalld
# firewall-cmd --state
# firewall-cmd --list-all                              # active zone, services, ports

# open a port permanently
# firewall-cmd --permanent --add-port=1521/tcp
# firewall-cmd --permanent --add-service=postgresql     # 5432
# firewall-cmd --permanent --add-service=mysql          # 3306
# firewall-cmd --reload

# allow only the application subnet (better than opening to everyone)
# firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/24" port port="5432" protocol="tcp" accept'
# firewall-cmd --reload

# remove
# firewall-cmd --permanent --remove-port=1521/tcp && firewall-cmd --reload
```

`--permanent` writes the config; without `--reload` it is not active yet. Without `--permanent` the rule is lost at reboot.

---

## Step 2 — ufw (Ubuntu)

```bash
# ufw status verbose
# ufw allow from 10.0.0.0/24 to any port 5432 proto tcp
# ufw delete allow 3306/tcp
# ufw enable
```

---

## Step 3 — SELinux basics

```bash
$ getenforce                  # Enforcing | Permissive | Disabled
$ sestatus
# setenforce 0                # ⚠️ Permissive until reboot — for TROUBLESHOOTING only
# setenforce 1
$ ls -Z /var/lib/pgsql        # show SELinux context of files
$ ps -eZ | grep postgres      # context of processes
```

**Did SELinux block something?**

```bash
# ausearch -m avc -ts recent
# grep denied /var/log/audit/audit.log | tail
# sealert -a /var/log/audit/audit.log          # human explanation + fix (setroubleshoot-server)
```

---

## Step 4 — Fix SELinux properly (instead of disabling it)

**New data directory** (e.g. PostgreSQL moved to `/pgdata`):

```bash
# semanage fcontext -a -t postgresql_db_t "/pgdata(/.*)?"
# restorecon -Rv /pgdata
```

MySQL on `/mysqldata`:

```bash
# semanage fcontext -a -t mysqld_db_t "/mysqldata(/.*)?"
# restorecon -Rv /mysqldata
```

**Non-default port** (PostgreSQL on 5433, MySQL on 3307):

```bash
# semanage port -l | grep -E 'postgresql|mysqld'
# semanage port -a -t postgresql_port_t -p tcp 5433
# semanage port -a -t mysqld_port_t -p tcp 3307
```

**Booleans:**

```bash
# getsebool -a | grep -E 'postgres|mysql|nfs'
# setsebool -P selinuxuser_postgresql_connect_enabled on
```

---

## Step 5 — SSH hardening for DB servers

`/etc/ssh/sshd_config` (or a file in `/etc/ssh/sshd_config.d/`):

```
PermitRootLogin no
PasswordAuthentication no        # keys only (set up keys first!)
AllowGroups dba wheel
ClientAliveInterval 300
```

```bash
# sshd -t && systemctl reload sshd     # test syntax, then reload — keep your current session open while testing
```

---

## Step 6 — Audit who did what

```bash
$ last -F | head                          # logins
# lastb | head                            # failed logins
# journalctl _COMM=sudo --since today     # sudo usage
# ausearch -k dba_config                  # custom audit key (below)

# watch changes to critical DB files
# auditctl -w /etc/oratab -p wa -k dba_config
# auditctl -w /var/lib/pgsql/16/data/pg_hba.conf -p wa -k dba_config
```

Make audit rules permanent in `/etc/audit/rules.d/dba.rules`.

---

## Step 7 — Protect secrets and files

```bash
$ chmod 600 ~/.pgpass ~/.my.cnf
$ find /home/oracle/scripts -type f -perm /o+r           # scripts readable by everyone?
$ grep -rIl -E 'password=|identified by' /home/oracle/scripts   # hard-coded passwords
```

Prefer Oracle Wallet / `mysql_config_editor` / `.pgpass` over passwords in scripts, and never pass a password as a command-line argument — it is visible in `ps -ef`.

---

## Step 8 — Keep the OS patched

```bash
# dnf check-update
# dnf updateinfo list security
# dnf update --security -y
$ needs-restarting -r          # does the server need a reboot? (dnf-utils)
# apt update && apt list --upgradable          # Ubuntu
```

Coordinate kernel updates with database maintenance windows, and re-check HugePages after reboot.
