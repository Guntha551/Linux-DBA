# 02 · Users, Groups & Permissions

**Goal:** Create and manage the OS accounts that own database software, and get file permissions right so the database can start.

---

## Step 1 — Create groups for the database

```bash
# groupadd -g 54321 oinstall      # Oracle inventory group
# groupadd -g 54322 dba           # SYSDBA privilege
# groupadd -g 54323 oper          # SYSOPER privilege
```

**Description:** `-g` fixes the GID. Use the **same GID on every node** of a RAC cluster or on servers sharing NFS; otherwise file ownership looks wrong across hosts.

---

## Step 2 — Create the database owner

```bash
# useradd -u 54321 -g oinstall -G dba,oper -m -s /bin/bash oracle
# passwd oracle
```

| Option | Meaning |
|--------|---------|
| `-u` | fixed UID |
| `-g` | primary group |
| `-G` | supplementary groups |
| `-m` | create home directory |
| `-s` | login shell |

For PostgreSQL/MySQL the packages create the user for you (`postgres`, `mysql`). Check with:

```bash
$ id postgres
$ getent passwd mysql
```

---

## Step 3 — Modify an existing user

```bash
# usermod -aG dba oracle        # ADD a supplementary group (-a is essential!)
# usermod -L olduser            # lock the account
# usermod -U olduser            # unlock
# chage -l oracle               # password expiry information
# chage -M -1 oracle            # ⚠️ disable password expiry (service accounts only)
```

**⚠️ Warning:** `usermod -G dba oracle` *without* `-a` **replaces** all supplementary groups.

---

## Step 4 — Switch to the database user

```bash
# su - oracle          # '-' loads oracle's profile (ORACLE_HOME, PATH ...)
$ sudo -iu postgres    # same idea via sudo
$ sudo -u postgres psql
```

Always use `su -` (with the dash). Plain `su oracle` keeps root's environment and causes "ORACLE_HOME not set" style errors.

---

## Step 5 — Understand permissions

```bash
$ ls -l /u01/app/oracle
drwxr-x---  5 oracle oinstall 4096 Jan 10 09:00 product
```

`d rwx r-x ---` = directory; owner can read/write/execute, group can read/execute, others have no access.

| Number | Permission |
|--------|------------|
| 4 | read (r) |
| 2 | write (w) |
| 1 | execute (x) |

---

## Step 6 — Change ownership and permissions

```bash
# chown -R oracle:oinstall /u01/app          # recursive owner:group
# chmod 775 /u01/app                         # rwxrwxr-x
# chmod 700 /var/lib/pgsql/16/data           # PostgreSQL REFUSES to start if the data dir is group/world readable
# chmod 750 /var/lib/mysql
$ chmod 600 ~/.pgpass ~/.my.cnf               # password files must be private
```

**Special bits DBAs meet:**

```bash
$ ls -l $ORACLE_HOME/bin/oracle
-rwsr-s--x 1 oracle asmadmin ... oracle     # 's' = setuid/setgid, required by Oracle
# chmod 6751 $ORACLE_HOME/bin/oracle         # restore if it gets lost after a copy
```

---

## Step 7 — Default permissions for new files (umask)

```bash
$ umask          # 0022 -> new files 644, new dirs 755
$ umask 0027     # new files 640, dirs 750 (put in ~/.bash_profile)
```

---

## Step 8 — Access control lists (give one extra user access)

```bash
# setfacl -m u:backupusr:rx /backup/rman      # grant read+execute to one user
$ getfacl /backup/rman                         # view ACLs
# setfacl -x u:backupusr /backup/rman          # remove
```

---

## Step 9 — sudo for DBAs

```bash
# visudo -f /etc/sudoers.d/dba
%dba ALL=(root) NOPASSWD: /usr/bin/systemctl restart postgresql-16, /usr/bin/systemctl status postgresql-16
$ sudo -l        # list what you are allowed to run
```

Always edit sudoers with `visudo` — it syntax-checks before saving, so you cannot lock yourself out.

---

## Step 10 — Who is logged in / what happened

```bash
$ who            # current sessions
$ w              # sessions + what they are running
$ last -n 20     # login history
$ lastb | head   # failed logins (root)
```
