#!/usr/bin/env bash
#
# top_resource_consumers.sh - top N processes by CPU, memory and swap.
#
# Usage: ./top_resource_consumers.sh [N]     (default N = 10)
# Use the PIDs shown here to find the matching database session
# (v$process.spid, pg_stat_activity.pid, performance_schema.threads.THREAD_OS_ID).

set -u

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

N=${1:-10}
if ! [[ $N =~ ^[0-9]+$ ]] || (( N < 1 )); then
    echo "N must be a positive number" >&2
    exit 2
fi

echo "===== TOP $N BY CPU ====="
ps -eo pid,user,%cpu,%mem,etime,args --sort=-%cpu | head -n $((N + 1)) | cut -c1-150

echo
echo "===== TOP $N BY MEMORY (RSS) ====="
ps -eo pid,user,rss,%mem,args --sort=-rss | head -n $((N + 1)) \
    | awk 'NR==1 {printf "%8s %-10s %10s %5s %s\n", "PID", "USER", "RSS_MB", "%MEM", "COMMAND"; next}
           {cmd=$5; for (i=6; i<=NF; i++) cmd=cmd " " $i
            printf "%8s %-10s %10.1f %5s %s\n", $1, $2, $3/1024, $4, substr(cmd, 1, 100)}'

echo
echo "===== TOP $N BY SWAP ====="
for status in /proc/[0-9]*/status; do
    awk '/^Name:/ {n=$2} /^Pid:/ {p=$2} /^VmSwap:/ {s=$2} END {if (s > 0) printf "%8s %10.1f %s\n", p, s/1024, n}' \
        "$status" 2>/dev/null
done | sort -k2 -nr | head -n "$N" \
    | awk 'BEGIN {printf "%8s %10s %s\n", "PID", "SWAP_MB", "NAME"} {print}'
