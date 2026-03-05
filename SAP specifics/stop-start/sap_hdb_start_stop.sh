#!/bin/bash
ACTION="$1"
SID="$2"
HDB_IN="$3"



########################################
# Usage function
########################################
usage() {
    # echo "Usage: $0 {start|stop} <SID> <HDB_instance_number>"
    exit 1
}


# Check if action and SID are provided
if [ -z "$ACTION" ] || [ -z "$SID" ] || [ -z "$HDB_IN" ] ; then
    usage
fi
if [[ "$ACTION" != "start" && "$ACTION" != "stop" ]]; then
    usage
fi

SID_LOWER=${SID,,}
LOGFILE="/usr/sap/${SID}/sap_hdb_start_stop.log"

if [ "$ACTION" = "start" ]; then
	LOGFILE="/usr/sap/${SID}/start_hana_db.log"
	echo "=== Starting HANA DB at $(date) ===" >> "$LOGFILE"
	# Step 1: StartService
	echo "Running StartService..." >> "$LOGFILE"
	su - ${SID_LOWER} -c "/usr/sap/hostctrl/exe/sapcontrol -nr ${HDB_IN}  -function StartService ${SID}" >> "$LOGFILE" 2>&1
	# Wait for 10 seconds
	echo "Sleeping for 10 seconds..." >> "$LOGFILE"
	sleep 10
	# Step 2: Start DB
	echo "Starting HANA DB..." >> "$LOGFILE"
	su - ${SID_LOWER} -c "/usr/sap/hostctrl/exe/sapcontrol -nr ${HDB_IN} -function StartWait 600 10" >> "$LOGFILE" 2>&1
	echo "=== HANA DB Startup Complete at $(date) ===" >> "$LOGFILE"

elif [ "$ACTION" = "stop" ]; then
	# Step 1: Stop DB
	echo "Stopping HANA DB..." >> "$LOGFILE"
	su - ${SID_LOWER} -c "/usr/sap/hostctrl/exe/sapcontrol -nr ${HDB_IN} -function StopWait 600 10" >> "$LOGFILE" 2>&1

	echo "=== HANA DB Stop Complete at $(date) ===" >> "$LOGFILE"	
fi