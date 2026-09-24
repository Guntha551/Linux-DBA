#!/usr/bin/env bash
# nareshsundaraneedi
# cleanup_old_files.sh - remove old trace / audit / log files. DRY RUN by default.
#
# Usage: ./cleanup_old_files.sh DIRECTORY PATTERN DAYS [--delete]
#   DIRECTORY  where to search (recursively, same filesystem only)
#   PATTERN    file name pattern, quoted, e.g. "*.trc" or "*.aud"
#   DAYS       delete files last modified more than DAYS days ago
#   --delete   actually delete; without it the files are only listed
#
# Examples:
#   ./cleanup_old_files.sh /u01/app/oracle/diag "*.tr[cm]" 7
#   ./cleanup_old_files.sh /u01/app/oracle/admin "*.aud" 30 --delete
#
# Do NOT use this for archive logs, pg_wal or MySQL binlogs - use RMAN,
# replication-slot/archiver fixes and PURGE BINARY LOGS instead.

set -u

usage() { sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 3 ]]; then
    usage
    [[ $# -lt 3 && "${1:-}" != "-h" && "${1:-}" != "--help" ]] && exit 2
    exit 0
fi

DIR=$1
PATTERN=$2
DAYS=$3
MODE=${4:-}

if [[ ! -d $DIR ]]; then
    echo "Directory not found: $DIR" >&2
    exit 2
fi
if ! [[ $DAYS =~ ^[0-9]+$ ]]; then
    echo "DAYS must be a whole number" >&2
    exit 2
fi
case $(realpath "$DIR") in
    / | /etc | /usr | /bin | /sbin | /lib | /lib64 | /boot | /var | /home)
        echo "Refusing to run on system directory: $DIR" >&2
        exit 2 ;;
esac

count=$(find "$DIR" -xdev -type f -name "$PATTERN" -mtime +"$DAYS" | wc -l)
size=$(find "$DIR" -xdev -type f -name "$PATTERN" -mtime +"$DAYS" -printf '%s\n' \
       | awk '{s+=$1} END {printf "%.1f MB", s/1024/1024}')

echo "Directory : $DIR"
echo "Pattern   : $PATTERN"
echo "Older than: $DAYS days"
echo "Matches   : $count files, $size"

if [[ $MODE == "--delete" ]]; then
    find "$DIR" -xdev -type f -name "$PATTERN" -mtime +"$DAYS" -delete
    echo "Deleted $count files."
else
    find "$DIR" -xdev -type f -name "$PATTERN" -mtime +"$DAYS" -printf '%TY-%Tm-%Td %10s  %p\n' | head -20
    (( count > 20 )) && echo "... ($((count - 20)) more)"
    echo
    echo "DRY RUN - nothing deleted. Add --delete to remove these files."
fi
