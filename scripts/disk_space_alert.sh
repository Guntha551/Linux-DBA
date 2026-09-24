#!/usr/bin/env bash
#
# disk_space_alert.sh - warn when any filesystem (space or inodes) crosses a threshold.
#
# Usage: ./disk_space_alert.sh [THRESHOLD_PERCENT] [EMAIL]
#   THRESHOLD_PERCENT  default 85
#   EMAIL              optional; sends the report with 'mail' if it is installed
# Exit code: 0 = all below threshold, 1 = at least one filesystem over threshold.
#
# Cron example (every 30 min):
#   */30 * * * * /opt/Linux-DBA/scripts/disk_space_alert.sh 85 dba@example.com

set -u

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

THRESHOLD=${1:-85}
EMAIL=${2:-}

if ! [[ $THRESHOLD =~ ^[0-9]+$ ]] || (( THRESHOLD < 1 || THRESHOLD > 100 )); then
    echo "Threshold must be a number between 1 and 100" >&2
    exit 2
fi

EXCLUDE=(-x tmpfs -x devtmpfs -x squashfs -x overlay -x iso9660)

report=$(
    {
        df -P "${EXCLUDE[@]}" 2>/dev/null | awk -v t="$THRESHOLD" \
            'NR>1 { p=$5; sub("%","",p); if (p+0 >= t) printf "SPACE  %4s%%  %s (%s)\n", p, $6, $1 }'
        df -iP "${EXCLUDE[@]}" 2>/dev/null | awk -v t="$THRESHOLD" \
            'NR>1 && $5 != "-" { p=$5; sub("%","",p); if (p+0 >= t) printf "INODES %4s%%  %s (%s)\n", p, $6, $1 }'
    }
)

if [[ -z $report ]]; then
    echo "OK: all filesystems below ${THRESHOLD}% on $(hostname)"
    exit 0
fi

msg="WARNING: filesystems at or above ${THRESHOLD}% on $(hostname) at $(date '+%F %T')
$report"

echo "$msg"

if [[ -n $EMAIL ]]; then
    if command -v mail >/dev/null 2>&1; then
        echo "$msg" | mail -s "Disk space alert: $(hostname)" "$EMAIL"
    else
        echo "'mail' command not found; email not sent" >&2
    fi
fi

exit 1
