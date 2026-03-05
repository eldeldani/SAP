#!/bin/bash
# Argument to variable assignment
ACTION="$1"
SID="$2"
ASCS_IN="$3"
APP_IN="$4"

########################################
# Usage function
########################################
usage() {
    # echo "Usage: $0 {start|stop} <SID> <ASCS_Instance_Number> <App_Instance_Number>"
    exit 1
}


# Check if action and SID are provided
if [ -z "$ACTION" ] || [ -z "$SID" ] || [ -z "$ASCS_IN" ] || [ -z "$APP_IN" ] ; then
    usage
fi
if [[ "$ACTION" != "start" && "$ACTION" != "stop" ]]; then
    usage
fi

SID_LOWER=${SID,,}
LOGFILE="/usr/sap/${SID}/sap_app_start_stop.log"

if [ "$ACTION" = "start" ]; then
	echo "===== SAP Application Startup Script Triggered at $(date) =====" >> "$LOGFILE"
	echo "Checking if SAP application can connect to HANA DB using R3trans -d..." >> "$LOGFILE"
	# Wait until SAP can connect to DB
	while true; do
		su - ${SID_LOWER}"adm" -c "R3trans -d" >> "$LOGFILE" 2>&1
		if [ $? -eq 0 ]; then
			echo "$(date): SAP Application can connect to DB. Proceeding with startup." >> "$LOGFILE"
			break
		else
			echo "$(date): R3trans -d failed. Waiting 10s before retrying..." >> "$LOGFILE"
			sleep 10
		fi
	done
	# Start Services
	echo "$(date): Starting SAP Services..." >> "$LOGFILE"
	su - ${SID_LOWER} -c "/usr/sap/hostctrl/exe/sapcontrol -nr ${ASCS_IN} -function StartService ${SID}" >> "$LOGFILE" 2>&1
	su - ${SID_LOWER} -c "/usr/sap/hostctrl/exe/sapcontrol -nr ${APP_IN} -function StartService ${SID}" >> "$LOGFILE" 2>&1
	# Start ASCS instance
	echo "$(date): Starting SAP ASCS Instance..." >> "$LOGFILE"
	su - ${SID_LOWER} -c "/usr/sap/hostctrl/exe/sapcontrol -nr ${ASCS_IN} -function StartWait 600 10" >> "$LOGFILE" 2>&1
	# Start App Server instance
	echo "$(date): Starting SAP App Server Instance..." >> "$LOGFILE"
	su - ${SID_LOWER} -c "/usr/sap/hostctrl/exe/sapcontrol -nr ${APP_IN} -function StartWait 600 10" >> "$LOGFILE" 2>&1
	echo "$(date): SAP ASCS and App Server started successfully." >> "$LOGFILE"

elif [ "$ACTION" = "stop" ]; then
	# Stop App Server instance
	echo "$(date): Stopping SAP App Server Instance..." >> "$LOGFILE"
	su - ${SID_LOWER} -c "/usr/sap/hostctrl/exe/sapcontrol -nr ${APP_IN} -function StopWait 600 10" >> "$LOGFILE" 2>&1
	# Stop ASCS instance
	echo "$(date): Starting SAP ASCS Instance..." >> "$LOGFILE"
	su - ${SID_LOWER}adm -c "/usr/sap/hostctrl/exe/sapcontrol -nr ${ASCS_IN} -function StopWait 600 10" >> "$LOGFILE" 2>&1
fi