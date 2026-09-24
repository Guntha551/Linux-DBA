# 12 · Oracle Database on Linux

**Goal:** The OS-level commands an Oracle DBA uses around the database: environment, start/stop, listener, ASM, patching checks and housekeeping.

---

## Step 1 — Set the environment

```bash
$ cat /etc/oratab                    # SID:ORACLE_HOME:autostart(Y/N)
ORCL:/u01/app/oracle/product/19.0.0/dbhome_1:Y

$ . oraenv                           # prompts for SID, sets ORACLE_HOME/PATH from oratab
ORACLE_SID = [oracle] ? ORCL

$ echo $ORACLE_SID $ORACLE_HOME $ORACLE_BASE
$ env | grep ORA
```

Typical `~/.bash_profile`:

```bash
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/19.0.0/dbhome_1
export ORACLE_SID=ORCL
export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/lib:/usr/lib
export NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS'
```

---

## Step 2 — Which instances are running?

```bash
$ ps -ef | grep [p]mon                     # [p] trick hides the grep itself
oracle  2345  1  0 Sep20 ?  00:01:12 ora_pmon_ORCL
$ ps -ef | grep [p]mon | awk -F_ '{print $NF}'   # just the SIDs
```

---

## Step 3 — Start and stop the database

```bash
$ sqlplus / as sysdba
SQL> startup;                 -- nomount -> mount -> open
SQL> shutdown immediate;      -- rolls back active transactions, clean
SQL> exit

$ srvctl status database -d ORCL      # Grid Infrastructure / RAC / Restart
$ srvctl stop database -d ORCL
$ srvctl start database -d ORCL
```

---

## Step 4 — Listener

```bash
$ lsnrctl status              # services registered, log location, uptime
$ lsnrctl services            # handlers per service
$ lsnrctl start | stop | reload
$ cat $ORACLE_HOME/network/admin/listener.ora
$ cat $ORACLE_HOME/network/admin/tnsnames.ora
$ tnsping ORCL
$ sqlplus system@//dbhost01:1521/ORCLPDB1     # EZConnect test without tnsnames
```

---

## Step 5 — ASM and Grid Infrastructure

```bash
$ . oraenv  <<< +ASM
$ asmcmd lsdg                 # disk groups: total/free MB, redundancy
$ asmcmd lsdsk -k             # disks and their paths
$ asmcmd du +DATA/ORCL        # space used by a database
$ crsctl stat res -t          # all cluster resources and their state
$ crsctl check crs            # CRS/CSS/EVM health
$ olsnodes -n -s              # cluster nodes
# oracleasm listdisks         # ASMLib disks  (or: ls -l /dev/oracleasm/, udev rules)
```

---

## Step 6 — Patching / inventory checks

```bash
$ $ORACLE_HOME/OPatch/opatch version
$ $ORACLE_HOME/OPatch/opatch lspatches            # installed patches
$ $ORACLE_HOME/OPatch/opatch lsinventory | grep -i 'patch description'
$ cd <patch_dir> && $ORACLE_HOME/OPatch/opatch prereq CheckConflictAgainstOHWithDetail -ph ./
$ cat /u01/app/oraInventory/ContentsXML/inventory.xml   # all Oracle homes on the host
$ $ORACLE_HOME/OPatch/datapatch -verbose           # apply SQL part of a patch after DB restart
```

---

## Step 7 — Diagnostics with ADRCI

```bash
$ adrci
adrci> show homes
adrci> set home diag/rdbms/orcl/ORCL
adrci> show alert -tail 100 -f          # follow alert log
adrci> show problem                      # critical errors (ORA-600, ORA-7445)
adrci> ips pack problem 1 in /tmp        # package for Oracle Support
adrci> purge -age 10080 -type TRACE      # delete traces > 7 days
```

---

## Step 8 — Archive log destination filling up

```bash
$ df -h /u03/arch
$ ls -ltr /u03/arch | tail
$ du -sh /u03/arch
```

**Never `rm` archive logs that RMAN has not backed up.** Use RMAN so the control file stays consistent:

```bash
$ rman target /
RMAN> backup archivelog all delete input;
RMAN> delete noprompt archivelog all completed before 'sysdate-2' backed up 1 times to device type disk;
RMAN> crosscheck archivelog all;     # after files were removed at OS level by mistake
RMAN> delete expired archivelog all;
```

---

## Step 9 — Audit and trace file housekeeping

```bash
$ find $ORACLE_BASE/admin/*/adump -name "*.aud" -mtime +30 | wc -l
$ find $ORACLE_BASE/admin/*/adump -name "*.aud" -mtime +30 -delete        # ⚠️ check retention policy first
$ find $ORACLE_BASE/diag -name "*.tr[cm]" -mtime +7 -delete
$ find $ORACLE_BASE/diag -name "cdump_*" -type d -mtime +30
```

---

## Step 10 — Useful one-liners

```bash
# Run a SQL query from the shell (for scripts)
$ sqlplus -s / as sysdba <<EOF
set pages 0 feed off head off
select name, open_mode, database_role from v\$database;
EOF

# Tablespace usage from the shell
$ sqlplus -s / as sysdba @/home/oracle/sql/ts_usage.sql

# Which Oracle home is a running instance using?
$ ls -l /proc/$(pgrep -f ora_pmon_ORCL)/exe
```
