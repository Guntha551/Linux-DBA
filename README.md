# Linux for DBAs

A hands-on reference of the Linux commands a Database Administrator (Oracle, PostgreSQL, MySQL/MariaDB) uses day to day, with a step-by-step explanation of each one: **what it does, when to use it, and how to read the output.**

> Tested on RHEL / Oracle Linux / Rocky 8–9 and Ubuntu 22.04+. Where the distributions differ, both commands are shown.

---

## Repository layout

```
Linux-DBA/
├── README.md                  <- you are here
├── CHEATSHEET.md              <- one-page quick reference
├── docs/
│   ├── 01-system-information.md
│   ├── 02-users-groups-permissions.md
│   ├── 03-filesystem-and-storage.md
│   ├── 04-memory-and-cpu.md
│   ├── 05-process-management.md
│   ├── 06-disk-io-performance.md
│   ├── 07-networking.md
│   ├── 08-logs-and-text-processing.md
│   ├── 09-kernel-parameters-hugepages.md
│   ├── 10-backup-compression-transfer.md
│   ├── 11-scheduling-cron-systemd.md
│   ├── 12-oracle-on-linux.md
│   ├── 13-postgresql-on-linux.md
│   ├── 14-mysql-on-linux.md
│   ├── 15-security-firewall-selinux.md
│   ├── 16-troubleshooting-scenarios.md
│   └── 17-high-cpu-process-investigation.md
└── scripts/
    ├── db_server_health_check.sh
    ├── disk_space_alert.sh
    ├── cleanup_old_files.sh
    └── top_resource_consumers.sh
```

## How to use this guide

| If you want to…                                   | Read                                                                 |
|---------------------------------------------------|----------------------------------------------------------------------|
| Learn a new server you just logged into           | [01 System information](docs/01-system-information.md)               |
| Create the `oracle` / `postgres` / `mysql` OS user | [02 Users, groups & permissions](docs/02-users-groups-permissions.md) |
| Add a disk, extend a filesystem, find space hogs  | [03 Filesystem & storage](docs/03-filesystem-and-storage.md)         |
| Find out why the server is slow                   | [04 Memory & CPU](docs/04-memory-and-cpu.md), [06 Disk I/O](docs/06-disk-io-performance.md) |
| Kill a hung session / runaway process             | [05 Process management](docs/05-process-management.md)               |
| Check listener / port / connectivity problems     | [07 Networking](docs/07-networking.md)                               |
| Search alert logs, trim trace files               | [08 Logs & text processing](docs/08-logs-and-text-processing.md)     |
| Set `shmmax`, semaphores, ulimits, HugePages       | [09 Kernel parameters & HugePages](docs/09-kernel-parameters-hugepages.md) |
| Copy dumps between servers, compress backups      | [10 Backup, compression & transfer](docs/10-backup-compression-transfer.md) |
| Schedule backups and maintenance jobs             | [11 Scheduling](docs/11-scheduling-cron-systemd.md)                  |
| Engine-specific OS tasks                          | [12 Oracle](docs/12-oracle-on-linux.md), [13 PostgreSQL](docs/13-postgresql-on-linux.md), [14 MySQL](docs/14-mysql-on-linux.md) |
| Open a port, deal with SELinux                    | [15 Security, firewall & SELinux](docs/15-security-firewall-selinux.md) |
| Walk through real incidents step by step          | [16 Troubleshooting scenarios](docs/16-troubleshooting-scenarios.md) |
| Find a high-CPU process: its user, command, what it is doing and its SQL | [17 High-CPU process investigation](docs/17-high-cpu-process-investigation.md) |

## Conventions

- `$` = run as the database OS user (`oracle`, `postgres`, `mysql`).
- `#` = run as `root` (or prefix with `sudo`).
- `<value>` = replace with your own value.
- Commands that change or delete things are marked **⚠️** — read the explanation before running them on production.

## Using the scripts

```bash
git clone https://github.com/guntha551/Linux-DBA.git
cd Linux-DBA/scripts
chmod +x *.sh
./db_server_health_check.sh            # one-shot health report
./disk_space_alert.sh 85               # warn on filesystems >= 85% full
./top_resource_consumers.sh 10         # top 10 CPU and memory processes
./cleanup_old_files.sh /u01/app/oracle/diag "*.trc" 7        # dry run
./cleanup_old_files.sh /u01/app/oracle/diag "*.trc" 7 --delete
```

Each script prints its usage with `-h`.

## Contributing

1. Fork the repo and create a branch.
2. Add or improve a command. Every command needs: syntax, an example, and a short description of what the output means.
3. Open a pull request.
