#!/bin/bash

PATH='/usr/sbin:/usr/bin:/sbin:/bin'
export PATH
LC_ALL=C
export LC_ALL

SID=${1:-}
THRESHOLD=${2:-}

if [ -z "$SID" ] || [ -z "$THRESHOLD" ]; then
    echo "$(date '+%F %T'): ERROR: Usage: $0 <SID> <threshold_percentage>" >&2
    exit 2
fi

case "$SID" in
    [[:alnum:]][[:alnum:]][[:alnum:]]) ;;
    *)
        echo "$(date '+%F %T'): ERROR: Invalid SID: $SID" >&2
        exit 2
        ;;
esac

case "$THRESHOLD" in
    ''|*[!0-9]*)
        echo "$(date '+%F %T'): ERROR: Threshold must be a numeric percentage." >&2
        exit 2
        ;;
esac

if [ "$THRESHOLD" -lt 1 ] || [ "$THRESHOLD" -gt 100 ]; then
    echo "$(date '+%F %T'): ERROR: Threshold must be between 1 and 100." >&2
    exit 2
fi

FILESYSTEM="/oracle/${SID}/oraarch"

if [ ! -d "$FILESYSTEM" ]; then
    echo "$(date '+%F %T'): ERROR: Directory does not exist: $FILESYSTEM" >&2
    exit 2
fi

# -P gives a predictable one-line-per-filesystem output format.
USAGE=$(
    df -P -k "$FILESYSTEM" 2>/dev/null |
    awk 'NR == 2 { gsub(/%/, "", $5); print $5 }'
)

case "$USAGE" in
    ''|*[!0-9]*)
        echo "$(date '+%F %T'): ERROR: Could not determine filesystem usage for $FILESYSTEM" >&2
        exit 1
        ;;
esac

echo "$(date '+%F %T'): SID=$SID THRESHOLD=$THRESHOLD FILESYSTEM=$FILESYSTEM USAGE=${USAGE}%"

if [ "$USAGE" -gt "$THRESHOLD" ]; then
    echo "$(date '+%F %T'): Filesystem usage is above threshold; deleting .dbf files older than 60 minutes."

    # First, log which files are going to be removed.
    find "$FILESYSTEM" -type f -name '*.dbf' -mmin +60 -print

    # Then delete them.
    find "$FILESYSTEM" -type f -name '*.dbf' -mmin +60 -delete
    rc=$?

    if [ "$rc" -ne 0 ]; then
        echo "$(date '+%F %T'): ERROR: File deletion failed; rc=$rc" >&2
        exit "$rc"
    fi
else
    echo "$(date '+%F %T'): Filesystem usage is at or below threshold; no files deleted."
fi
