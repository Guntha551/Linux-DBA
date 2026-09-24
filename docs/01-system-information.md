# 01 · System Information

**Goal:** The first five minutes on an unfamiliar database server. Find out what OS, hardware, and uptime you are working with before you touch the database.

---

## Step 1 — Who and where am I?

```bash
$ whoami            # current OS user
$ id                # uid, gid and every group you belong to
$ hostname -f       # fully qualified host name
$ hostname -I       # all IP addresses of this host
```

**Why it matters:** The Oracle/PostgreSQL/MySQL software is owned by a specific user. `id` must show groups such as `oinstall`, `dba`, `postgres` or `mysql`; if they are missing, you will hit permission errors.

---

## Step 2 — Operating system and kernel version

```bash
$ cat /etc/os-release        # distribution name and version (all distros)
$ cat /etc/redhat-release    # RHEL / OL / Rocky / CentOS only
$ uname -r                   # kernel release, e.g. 5.15.0-209.el8uek.x86_64
$ uname -a                   # kernel + architecture + hostname
$ hostnamectl                # OS, kernel, architecture, virtualization in one view
```

**Why it matters:** Database certification matrices (e.g. Oracle 19c on OL8) depend on the OS and kernel version. `uek` in the kernel name means Oracle's Unbreakable Enterprise Kernel.

---

## Step 3 — How long has the server been up?

```bash
$ uptime
 10:42:13 up 45 days,  3:12,  2 users,  load average: 1.20, 0.95, 0.80

$ uptime -s          # exact boot time
$ last reboot | head # reboot history
```

**Reading it:** The three *load average* numbers are the 1, 5 and 15-minute averages of processes that are running or waiting (CPU or disk). Compare them with the CPU count (Step 4): a load consistently higher than the number of CPUs means the server is saturated.

---

## Step 4 — CPU details

```bash
$ nproc                          # number of usable CPUs
$ lscpu                          # sockets, cores, threads, model, NUMA nodes
$ grep -c ^processor /proc/cpuinfo
```

Key `lscpu` lines:

| Field | Meaning for a DBA |
|-------|-------------------|
| `Socket(s)` | Physical CPUs — used for licensing (Oracle, SQL Server) |
| `Core(s) per socket` | Physical cores |
| `Thread(s) per core` | 2 = Hyper-Threading is on |
| `NUMA node(s)` | >1 means memory locality matters for large SGA/shared_buffers |

---

## Step 5 — Memory and swap

```bash
$ free -h                     # human-readable RAM and swap summary
$ grep -E 'MemTotal|MemAvailable|SwapTotal|HugePages' /proc/meminfo
```

Look at the **`available`** column, not `free`. Linux uses spare RAM for the page cache, so `free` is always small on a healthy system. See [04 Memory & CPU](04-memory-and-cpu.md) for more.

---

## Step 6 — Disks and filesystems

```bash
$ lsblk                       # block devices as a tree (disk -> partition -> LVM)
$ df -hT                      # mounted filesystems with type and usage
$ cat /etc/fstab              # what gets mounted at boot
```

Typical DBA mount points: `/u01` (Oracle binaries), `/u02` (datafiles), `/var/lib/pgsql`, `/var/lib/mysql`, `/backup`.

---

## Step 7 — Is this a VM, a container, or bare metal?

```bash
$ systemd-detect-virt         # kvm, vmware, microsoft, none ...
# dmidecode -s system-product-name
# dmidecode -t memory | grep -E 'Size|Speed' | sort | uniq -c
```

**Why it matters:** VMs can have CPU steal time and thin-provisioned storage — both hurt database performance.

---

## Step 8 — Installed packages

```bash
$ rpm -qa | grep -i -E 'oracle|postgres|mysql|mariadb'   # RHEL family
$ rpm -q libaio ksh compat-openssl11                     # check a specific prerequisite
$ dpkg -l | grep -i -E 'postgres|mysql|mariadb'          # Debian/Ubuntu
```

---

## One-liner summary

```bash
echo "Host: $(hostname -f) | OS: $(. /etc/os-release; echo $PRETTY_NAME) | Kernel: $(uname -r) | CPUs: $(nproc) | RAM: $(free -h | awk '/Mem:/{print $2}') | Up: $(uptime -p)"
```
