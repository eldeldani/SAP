#!/bin/bash
# Emergency deletion of archives script
# Version 1.0
# By Daniel Munoz
# Usage:
# ./deletion_archives <SID> <threshold>
# It will delete *.dbf archives from /oracle/<SID>/oraarch filesystem when usage threshold is same or greather than <threshold>
FS=$1
TH=$2
USED=`df -h /oracle/$FS/oraarch |tail -1|awk '{print $5}' |sed 's/%//'`
if [ $USED -ge $TH ];then
echo "delete command"
find /oracle/$FS/oraarch/ -name "*.dbf" -mtime +1 -exec ls -lad {} \;
else
echo "nothing to do"
fi
