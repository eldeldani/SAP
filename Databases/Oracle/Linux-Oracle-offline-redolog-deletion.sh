#!/bin/bash

# Define the threshold
SID=$1
THRESHOLD=$2

# Define the filesystem path
FILESYSTEM="/oracle/"$SID"/oraarch"

while true; do
# Get the filesystem usage percentage
USAGE=$(df -h $FILESYSTEM | awk 'NR==2 {print $5}' | sed 's/%//')

# Check if usage is above the threshold
if [ "$USAGE" -gt "$THRESHOLD" ]; then
    echo "$(date): Filesystem "$FILESYSTEM" usage is "$USAGE"% which is above "$THRESHOLD"%"
    echo "$(date): Deleting files"
    echo "$(date): Command:"
    echo "$(date): find $FILESYSTEM -name "*.dbf" -mmin +60 -delete"
    find $FILESYSTEM -name "*.dbf" -mmin +60 -delete
else
    echo "$(date): Filesystem usage for "$FILESYSTEM" is "$USAGE"% which is LOWER than "$THRESHOLD""
fi
echo "$(date): Waiting for 1 minute..."
sleep 60
done