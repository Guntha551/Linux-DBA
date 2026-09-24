#!/usr/bin/env bash
#
# db_server_health_check.sh - one-shot OS health report for a database server.
#
# Usage: ./db_server_health_check.sh [-h]
# Read-only: it changes nothing. Some sections show more detail when run as root.

set -u

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

section() { printf '\n===== %s =====\n' "$1"; }
have()    { command -v "$1" >/dev/null 2>&1; }

section "HOST"
echo "Host      : $(hostname -f 2>/dev/null || hostname)"
echo "OS        : $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")"
echo "Kernel    : $(uname -r)"
echo "Uptime    : $(uptime -p 2>/dev/null || uptime)"
echo "CPUs      : $(nproc)"
echo "Load avg  : $(cut -d' ' -f1-3 /proc/loadavg)"
echo "Report at : $(date '+%F %T')"

section "MEMORY"
free -h
grep -E '^(HugePages_Total|HugePages_Free|Hugepagesize)' /proc/meminfo
thp=/sys/kernel/mm/transparent_hugepage/enabled
[[ -r $thp ]] && echo "THP       : $(cat $thp)"
echo "Swappiness: $(cat /proc/sys/vm/swappiness)"

section "CPU / RUN QUEUE (vmstat 1 3)"
vmstat 1 3

section "FILESYSTEMS >= 80% (space or inodes)"
df -hPT -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null \
    | awk 'NR==1 || $6+0 >= 80'
df -iP -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null \
    | awk 'NR>1 && $5+0 >= 80 {print "INODES " $5 " used on " $6}'

section "DISK I/O (iostat)"
if have iostat; then
    iostat -xz 1 2 | awk '/^avg-cpu|^Device/{blk++} blk>=3'
else
    echo "iostat not installed (package: sysstat)"
fi

section "TOP 5 CPU PROCESSES"
ps -eo pid,user,%cpu,%mem,etime,comm --sort=-%cpu | head -6

section "TOP 5 MEMORY PROCESSES"
ps -eo pid,user,rss,%mem,comm --sort=-rss | head -6

section "DATABASE PROCESSES"
found=0
if pgrep -f 'ora_pmon_' >/dev/null; then
    echo "Oracle instances : $(pgrep -af 'ora_pmon_' | awk -F'ora_pmon_' '{print $2}' | xargs)"
    found=1
fi
if pgrep -f tnslsnr >/dev/null; then
    echo "Oracle listener  : running"
    found=1
fi
if pgrep -x postgres >/dev/null || pgrep -x postmaster >/dev/null; then
    echo "PostgreSQL       : running ($(pgrep -x postgres | wc -l) processes)"
    found=1
fi
if pgrep -x mysqld >/dev/null || pgrep -x mariadbd >/dev/null; then
    echo "MySQL/MariaDB    : running"
    found=1
fi
(( found )) || echo "No Oracle / PostgreSQL / MySQL processes found"

section "LISTENING DATABASE PORTS"
if have ss; then
    ss -tln | awk 'NR==1 || /:(1521|1522|5432|3306|33060) /'
fi

section "RECENT KERNEL ERRORS / OOM"
if dmesg -T >/dev/null 2>&1; then
    kerr=$(dmesg -T | grep -i -E 'out of memory|killed process|i/o error|blk_update_request' | tail -5)
    echo "${kerr:-none}"
else
    echo "dmesg not readable (run as root for this section)"
fi

section "ZOMBIE / D-STATE PROCESSES"
ps -eo pid,stat,comm | awk 'NR==1 || $2 ~ /^[ZD]/'

echo
echo "Health check finished."
