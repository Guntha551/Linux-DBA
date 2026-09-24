#!/usr/bin/env bash
#
# cpu_by_database.sh - current CPU usage grouped by database instance.
#
# Usage: ./cpu_by_database.sh [SECONDS] [-v]
#   SECONDS  sampling interval, default 5
#   -v       also list the 20 busiest processes and the group they belong to
#
# Groups: Oracle DB instances (ora_*_SID, oracleSID), ASM (+ASM, incl. ASM work done
# for a DB: oracle+ASM1_asmb_orcl1 -> "for orcl1"), APX, MGMTDB, listeners,
# PostgreSQL databases (from the process title), MySQL instances (by port), and
# everything else by [user] program name (e.g. Grid Infrastructure ocssd.bin).
# 100% = one full CPU. Run as root to see all users (grid, oracle, postgres, mysql).
# Read-only; uses only /proc (no strace/perf), safe on production.

set -u

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

INTERVAL=5
VERBOSE=0
for arg in "$@"; do
    case $arg in
        -v) VERBOSE=1 ;;
        *[!0-9]* | '') echo "Unknown argument: $arg (see -h)" >&2; exit 2 ;;
        *) INTERVAL=$arg ;;
    esac
done
(( INTERVAL >= 1 )) || { echo "SECONDS must be >= 1" >&2; exit 2; }

HZ=$(getconf CLK_TCK)
NCPU=$(nproc)

# CPU ticks (user + system) of every process, read without forking one command per PID.
declare -A T1 T2
snapshot() {                       # $1 = 1 -> T1, 2 -> T2 (no namerefs: works on bash 4.2 / OL7)
    local f line pid
    for f in /proc/[0-9]*/stat; do
        IFS= read -r line < "$f" 2>/dev/null || continue
        pid=${f#/proc/}; pid=${pid%/stat}
        line=${line##*) }          # drop "pid (comm) " - comm may contain spaces
        local -a f2=($line)       # f2[0] = state, f2[11] = utime, f2[12] = stime
        if [[ $1 == 1 ]]; then T1[$pid]=$(( f2[11] + f2[12] )); else T2[$pid]=$(( f2[11] + f2[12] )); fi
    done
}

PG_RE='^postgres: (([^ ]+): )?([^ ]+) ([^ ]+) ([^ ]+\([0-9]+\)|\[local\])'

# Decide which database / component a PID belongs to.
classify() {
    local pid=$1 a0 comm port x
    local -a args=()
    while IFS= read -r -d '' x; do args+=("$x"); done < /proc/"$pid"/cmdline 2>/dev/null
    a0=${args[0]:-}
    a0=${a0%% *}                   # "oracleORCL1 (LOCAL=NO)" may be one string
    IFS= read -r comm < /proc/"$pid"/comm 2>/dev/null || comm=unknown

    case $a0 in
        ora_*_*)  x=${a0#ora_}; echo "Oracle DB     ${x#*_}"; return ;;
        asm_*_*)  x=${a0#asm_}; echo "Oracle ASM    ${x#*_}"; return ;;
        apx_*_*)  x=${a0#apx_}; echo "Oracle APX    ${x#*_}"; return ;;
        mdb_*_*)  x=${a0#mdb_}; echo "Oracle MGMTDB ${x#*_}"; return ;;
        oracle+ASM*|oracle+APX*)
            x=${a0#oracle}
            if [[ $x == *_* ]]; then echo "Oracle ASM    ${x%%_*} (for ${x##*_})"
            else echo "Oracle ASM    $x"; fi
            return ;;
        oracle-MGMTDB*) echo "Oracle MGMTDB -MGMTDB"; return ;;
        oracle?*) echo "Oracle DB     ${a0#oracle}"; return ;;
    esac

    if [[ $comm == tnslsnr ]]; then
        echo "Listener      ${args[1]:-tnslsnr}"; return
    fi

    x="${args[*]:-}"
    if [[ $x =~ $PG_RE ]]; then
        echo "PostgreSQL    ${BASH_REMATCH[2]:+${BASH_REMATCH[2]}/}${BASH_REMATCH[4]}"; return
    fi
    if [[ $x == postgres:* || $comm == postgres || $comm == postmaster ]]; then
        echo "PostgreSQL    (background)"; return
    fi

    if [[ $comm == mysqld || $comm == mariadbd ]]; then
        port=3306
        for x in "${args[@]}"; do [[ $x == --port=* ]] && port=${x#--port=}; done
        echo "MySQL         port $port"; return
    fi

    local uid
    uid=$(awk '/^Uid:/ {print $2; exit}' /proc/"$pid"/status 2>/dev/null)
    echo "Other         [$(username "${uid:-?}")] $comm"
}

declare -A UNAME
username() {
    local uid=$1
    if [[ -z ${UNAME[$uid]:-} ]]; then
        UNAME[$uid]=$(getent passwd "$uid" | cut -d: -f1)
        [[ -z ${UNAME[$uid]} ]] && UNAME[$uid]=$uid
    fi
    echo "${UNAME[$uid]}"
}

snapshot 1
sleep "$INTERVAL"
snapshot 2

declare -A GROUP_TICKS
PROC_LINES=""
total=0
for pid in "${!T2[@]}"; do
    d=$(( T2[$pid] - ${T1[$pid]:-0} ))   # new process: all its ticks were used during the interval
    (( d > 0 )) || continue
    g=$(classify "$pid")
    GROUP_TICKS[$g]=$(( ${GROUP_TICKS[$g]:-0} + d ))
    total=$(( total + d ))
    if (( VERBOSE )); then
        cmd=$(tr '\0' ' ' < /proc/"$pid"/cmdline 2>/dev/null | cut -c1-60)
        PROC_LINES+="$d"$'\t'"$pid"$'\t'"$g"$'\t'"${cmd:-?}"$'\n'
    fi
done

pct() { awk -v t="$1" -v hz="$HZ" -v s="$INTERVAL" 'BEGIN {printf "%.1f", t / hz / s * 100}'; }

echo "CPU by database on $(hostname) - ${INTERVAL}s sample at $(date '+%F %T')"
echo "CPUs: $NCPU (100% = one CPU, server maximum = $((NCPU * 100))%)"
echo
printf '%-45s %8s %9s\n' "GROUP" "%CPU" "%SERVER"
printf '%-45s %8s %9s\n' "-----" "----" "-------"
for g in "${!GROUP_TICKS[@]}"; do
    printf '%s\t%s\n' "${GROUP_TICKS[$g]}" "$g"
done | sort -nr | head -25 | while IFS=$'\t' read -r t g; do
    p=$(pct "$t")
    printf '%-45.45s %8s %8.1f%%\n' "$g" "$p" "$(awk -v p="$p" -v n="$NCPU" 'BEGIN {print p / n}')"
done
echo
printf '%-45s %8s %8.1f%%\n' "TOTAL (processes still running)" "$(pct "$total")" \
    "$(awk -v p="$(pct "$total")" -v n="$NCPU" 'BEGIN {print p / n}')"

if (( VERBOSE )); then
    echo
    echo "Top 20 processes:"
    printf '%8s %8s  %-40s %s\n' "PID" "%CPU" "GROUP" "COMMAND"
    printf '%s' "$PROC_LINES" | sort -nr | head -20 | while IFS=$'\t' read -r t pid g cmd; do
        printf '%8s %8s  %-40s %s\n' "$pid" "$(pct "$t")" "$g" "$cmd"
    done
fi
