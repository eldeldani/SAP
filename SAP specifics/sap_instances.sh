#!/bin/bash
# Do not exit the script automatically if a command returns non-zero.
# Some functions intentionally return non-zero to indicate partial failures
# but we need the caller loops to continue. Ensure 'errexit' is disabled.
# This script allows you to manage SAP instances and associated databases on a host.
# Created by Daniel Munoz
# For usage information, run:
#   sap_instances.sh 
# sap_instances.sh <command> [<option>]
# <command> can be:
#   instance_list [<SID>|all|<empty>]: 
#       lists all SAP instances found on the host
#   instance_status [detail|<SID>|<empty>] [<SID>]: 
#       shows the status of SAP instances found on the host
#   instance_version [<SID>|<empty>]:
#       shows the version of SAP instances found on the host
#   system_stop: stops SAP systems found on the host without the database. In case of HANA databases, the database will be stopped as part of the instance stop.
#   system_start: starts SAP systems found on the host without the database. In case of HANA databases, the database will be started as part of the instance start.
#   system_restart: restarts SAP systems found on the host without the database. In case of HANA databases, the database will be restarted as part of the instance restart.
#   db_list: lists all database systems found on the host.
#   db_status: shows the status of database instances found on the host
#   db_stop: stops non-HANA database instances found on the host
#   db_start: starts non-HANA database instances found on the host
#   db_restart: restarts non-HANA database instances found on the host
#   db_type: shows the type of database instances found on the host
#   all_stop: stops all instances -including HANA instances- and non-HANA databases found on the host
#   all_start: starts all instances -including HANA instances- and non-HANA databases found on the host
#   all_restart: stops/starts all instances -including HANA intances- and non-HANA databases on the host
# <option> is an optional parameter depending on the command used.

# Example:
# sap_instances.sh instance_list [<SID>|all|<empty>]
# sap_instances.sh instance_status [detail|<SID>|<empty>] [<SID>]
# sap_instances.sh instance_version [<SID>|<empty>]
# sap_instances.sh system_status <SID|all>
# sap_instances.sh system_stop <SID|all>
# sap_instances.sh system_start <SID|all>
# sap_instances.sh system_restart <SID|all>
# sap_instances.sh db_list 
# sap_instances.sh db_status <DBNAME|all|<empty>}
# sap_instances.sh db_stop <DBNAME>
# sap_instances.sh db_start <DBNAME>
# sap_instances.sh db_restart <DBNAME>
# sap_instances.sh db_type <DBNAME>
# sap_instances.sh all_stop
# sap_instances.sh all_start
# sap_instances.sh all_restart

# Test mode
declare testexec=0

# Global arrays
# - systems
declare -a sap_systems_array
declare -a sap_abap_systems_array
declare -a sap_java_systems_array
declare -a sap_hdb_systems_array
declare -a sap_contentserver_systems_array
declare -a db_systems_array
# - instances
declare -a sap_instances_array
declare -a sap_ascs_instances_array
declare -a sap_abap_instances_array
declare -a sap_scs_instances_array
declare -a sap_java_instances_array
declare -a sap_hdb_instances_array
declare -a sap_contentserver_instances_array
declare -a sap_daa_instances_array
declare -a sap_instances_all_array

# Global variables
declare sap_instances_found=0
declare saprouter_instance_found=0
declare db_systems_found=0
declare sap_systems_found=0
declare sap_abap_instances_found=0
declare sap_hdb_instances_found=0
declare sap_contentserver_instances_found=0
declare sap_ascs_instances_found=0
declare sap_scs_instances_found=0
declare sap_instances_found=0
declare sap_java_instances_found=0
declare saprouter_instance_found=0
declare SAPROUTER_INFO_FILE="/tmp/saprouter_info.txt"
declare SAPROUTER_STOPPED_WITH_SCRIPT="/tmp/saprouter_stopped_with_script.txt"


function_find_sap_instances(){
    if ! [ -f /usr/sap/sapservices ]; then
        return 1
    else
        while IFS= read -r line; do
            # Use a regular expression to extract the required part
            if [[ $line != \#* && $line =~ /usr/sap/([a-zA-Z0-9]{3})/SYS/profile/([a-zA-Z0-9]{3,5})_(D|DVEBMGS|ASCS|SCS|J|C|HDB)([0-9]{2})_([a-zA-Z0-9-]{1,13}) ]]; then
                SID=${BASH_REMATCH[1]}
                PROFSTRT=${BASH_REMATCH[2]}
                INSTANCE_TYPE=${BASH_REMATCH[3]}
                SN=${BASH_REMATCH[4]}
                VHOSTNAME=${BASH_REMATCH[5]}
                sap_instances_array+=("$SID")
                sap_instances_array+=("$PROFSTRT")
                sap_instances_array+=("$INSTANCE_TYPE")
                sap_instances_array+=("$SN")
                sap_instances_array+=("$VHOSTNAME")
                if [[ ! " ${sap_systems_array[@]} " =~ " ${SID} " ]]; then
                    sap_systems_array+=("$SID")
                fi
                if [[ "$INSTANCE_TYPE" == "J" ]]; then
                    sap_java_instances_found=1
                    if ! [[ " ${sap_java_systems_array[@]} " =~ " ${SID} " ]]; then
                        sap_java_systems_array+=("$SID")
                    fi
                    sap_java_instances_array+=("$SID")
                    sap_java_instances_array+=("$PROFSTRT")
                    sap_java_instances_array+=("$INSTANCE_TYPE")
                    sap_java_instances_array+=("$SN")
                    sap_java_instances_array+=("$VHOSTNAME")
                fi
                if [[ "$INSTANCE_TYPE" == D* ]]; then
                    sap_abap_instances_found=1
                    if ! [[ " ${sap_abap_systems_array[@]} " =~ " ${SID} " ]]; then
                        sap_abap_systems_array+=("$SID")
                    fi
                    sap_abap_instances_array+=("$SID")
                    sap_abap_instances_array+=("$PROFSTRT")
                    sap_abap_instances_array+=("$INSTANCE_TYPE")
                    sap_abap_instances_array+=("$SN")
                    sap_abap_instances_array+=("$VHOSTNAME")
                fi
                if [[ "$INSTANCE_TYPE" == "HDB" ]]; then
                    sap_hdb_instances_found=1
                    if ! [[ " ${sap_hdb_systems_array[@]} " =~ " ${SID} " ]]; then
                        sap_hdb_systems_array+=("$SID")
                    fi
                    sap_hdb_instances_array+=("$SID")
                    sap_hdb_instances_array+=("$PROFSTRT")
                    sap_hdb_instances_array+=("$INSTANCE_TYPE")
                    sap_hdb_instances_array+=("$SN")
                    sap_hdb_instances_array+=("$VHOSTNAME")
                fi
                if [[ "$INSTANCE_TYPE" == "C" ]]; then
                    sap_contentserver_instances_found=1
                    if ! [[ " ${sap_contentserver_systems_array[@]} " =~ " ${SID} " ]]; then
                        sap_contentserver_systems_array+=("$SID")
                    fi
                fi
                if [[ "${INSTANCE_TYPE}" == "ASCS" ]]; then
                    sap_ascs_instances_found=1
                    sap_ascs_instances_array+=("$SID")
                    sap_ascs_instances_array+=("$PROFSTRT")
                    sap_ascs_instances_array+=("$INSTANCE_TYPE")
                    sap_ascs_instances_array+=("$SN")
                    sap_ascs_instances_array+=("$VHOSTNAME")

                fi
                if [[ "${INSTANCE_TYPE}" == "SCS" ]]; then
                    sap_scs_instances_found=1
                    sap_scs_instances_array+=("$SID")
                    sap_scs_instances_array+=("$PROFSTRT")
                    sap_scs_instances_array+=("$INSTANCE_TYPE")
                    sap_scs_instances_array+=("$SN")
                    sap_scs_instances_array+=("$VHOSTNAME")
                fi
                sap_systems_found=1
            elif [[ $line != \#* && $line =~ /usr/sap/([a-zA-Z0-9]{3})/SYS/profile/([a-zA-Z0-9]{3,5})_(SMDA)([0-9]{2})_([a-zA-Z0-9-]{1,13}) ]]; then
                SID=${BASH_REMATCH[1]}
                PROFSTRT=${BASH_REMATCH[2]}
                INSTANCE_TYPE=${BASH_REMATCH[3]}
                SN=${BASH_REMATCH[4]}
                VHOSTNAME=${BASH_REMATCH[5]}
                sap_daa_instances_array+=("$SID")
                sap_daa_instances_array+=("$PROFSTRT")
                sap_daa_instances_array+=("$INSTANCE_TYPE")
                sap_daa_instances_array+=("$SN")
                sap_daa_instances_array+=("$VHOSTNAME")
            fi
            
        done < "/usr/sap/sapservices"
        sap_instances_all_array=( "${sap_instances_array[@]}" "${sap_daa_instances_array[@]}" )
        sap_instances_found=1
    fi
    # Uncomment for debugging
    # echo "==== Specifics ===="
    # echo "SAP ABAP systems found: ${sap_abap_systems_array[@]}"
    # echo "SAP ABAP instances found: ${sap_abap_instances_array[@]}"
    # echo "SAP ASCS instances found: ${sap_ascs_instances_array[@]}"
    # echo "SAP JAVA systems found: ${sap_java_systems_array[@]}"
    # echo "SAP JAVA instances found: ${sap_java_instances_array[@]}"
    # echo "SAP SCS instances found: ${sap_scs_instances_array[@]}"
    # echo "SAP HDB systems found: ${sap_hdb_systems_array[@]}"
    # echo "SAP HDB instances found: ${sap_hdb_instances_array[@]}"
    # echo "SAP Content Server systems found: ${sap_contentserver_systems_array[@]}"
    # echo "SAP Content Server instances found: ${sap_contentserver_instances_array[@]}"
    # echo "SAP DAA instances found: ${sap_daa_instances_array[@]}"
    # echo "==== global ===="
    # echo "SAP ALL systems found: ${sap_systems_array[@]}"
    # echo "SAP instances found: ${sap_instances_array[@]}"
    # echo "SAP ALL instances found: ${sap_instances_all_array[@]}"
    # echo ""
    # echo ""
    # echo ""
    
}
function_find_db_systems(){
    if ! [ -x "/usr/sap/hostctrl/exe/saphostctrl" ]; then
        echo "! Error: /usr/sap/hostctrl/exe/saphostctrl not found or not executable. Can not detect database instances."
        return 1
    else
        # capture full command output (stdout+stderr) without printing it
        local raw_db_output
        raw_db_output=$(/usr/sap/hostctrl/exe/saphostctrl -function ListDatabaseSystems 2>&1)

        # keep the filtered lines used by the script, stored in db_list_output
        local db_list_output
        db_list_output=$(printf "%s" "$raw_db_output" | grep "Database name")
        if [[ -z "$db_list_output" ]]; then 
            # echo "No database instances found."
            return 1
        else
            while IFS= read -r line; do
                db_sid=$(echo "$line" | awk -F', ' '{print $1}' | awk '{print $3}')
                if [[ "$db_sid" != *@* ]]; then
                    db_systems_array+=("$db_sid")
                fi
            done <<< "$db_list_output"
            db_systems_found=1
        fi
    fi
}
function_instance_type(){
    case $1 in
    D)
        echo "Dialog (D)"
        ;;
    DVEBMGS)
        echo "Dialog Central (DVEBMGS)"
        ;;
    ASCS)
        echo "ABAP Central Services (ASCS)"
        ;;
    SCS)
        echo "JAVA Central Services (SCS)"
        ;;
    J)
        echo "JAVA (J)"
        ;;
    C)
        echo "Content Server"
        ;;
    SMDA)
        echo "Solution Manager Diagnostics (SMDA)"
        ;;
    HDB)
        echo "HANA Database (HDB)"
        ;;
    *)
        echo "Unknown"
        ;;
    esac
}
# DISPLAY HELP FUNCTION
function_display_help(){
    echo "Usage: $0 <command> [<option>]"
    echo "  <command> must be one of the following:"
    echo "    instance_list [<SID>|all|<empty>]: lists all SAP instances found on the host"
    echo "    instance_status [detail|<SID>|<empty>] [<SID>]: shows the status of SAP instances found on the host for the given SID or all instances if no SID is provided"
    echo "    instance_version [<SID>|<empty>]: shows the version of SAP instances found on the host for the given SID or all instances if no SID is provided"
    echo "    system_stop <SID|all>: stops SAP systems found on the host without the database. In case of HANA databases, the database will be stopped as part of the instance stop. If JAVA instances are found, they will be stopped first followed by ABAP instances. IF ASCS/SCS instances are found, they will be stopped last. If HDB instances are found, they will be stopped lasts."
    echo "    system_start <SID|all>: starts SAP systems found on the host without the database. In case of HANA databases, the database will be started as part of the instance start."
    echo "    system_restart <SID|all>: restarts SAP systems found on the host without the database. In case of HANA databases, the database will be restarted as part of the instance restart."
    echo "    db_list: lists all database systems found on the host."
    echo "    db_status <DBNAME|all|<empty>}: shows the status of database instances found on the host"
    echo "    db_stop <DBNAME>: stops non-HANA database instances found on the host"
    echo "    db_start <DBNAME>: starts non-HANA database instances found on the host"
    echo "    db_restart <DBNAME>: restarts non-HANA database instances found on the host"
    echo "    db_type <DBNAME>: shows the type of database instances found on the host"
    echo "    all_stop: stops all instances -including HANA instances- and non-HANA databases found on the host"
    echo "    all_start: starts all instances -including HANA instances- and non-HANA databases found on the host"
    echo "    all_restart: stops/starts all instances -including HANA intances- and non-HANA databases on the host"

}
# DATABASE FUNCTIONS
function_db_list(){
    if [ "$db_systems_found" -eq 0 ]; then
        echo "No database instances found."
        return 1
    else
        for db_sid in "${db_systems_array[@]}"; do
            echo "$db_sid"
        done
    fi
}   
function_db_type(){
    if [ "$db_systems_found" -eq 0 ]; then
        echo "No database instances found."
        return 1
    else
        local db_name="${1^^}"
        if [[ -z "$db_name" || ${#db_name} -ne 3 && ! "$db_name" == *"@"* ]]; then
            echo "! Error: Database name not supplied or not having exactly 3 characters"
            return 1
        else
            local dboutput=$(/usr/sap/hostctrl/exe/saphostctrl -function ListDatabaseSystems|grep "Database name: ${db_name}")
            if [[ -z "$dboutput" ]]; then
                echo "! Error: Unable to find database '$db_name' in saphostctrl output"
                # echo "Available databases are: ${db_instances_array[@]}"
                return 1
            else
                # dbinstance=$(echo "$dboutput" | grep -i instance | awk -F', *' '{print $1}' | awk -F': *' '{print $2}')
                echo $dboutput |head -1| awk -F'Type: ' '{ split($2, a, ","); print a[1] }'
                # dbname=$(echo "$dboutput" | grep -i "database name" | awk -F', *' '{print $1}' | awk -F': *' '{print $2}')
            fi
        fi
    fi

}
db_type_friendly_name(){
    case $1 in
    hdb)
        echo "HANA"
        ;;
    ora)
        echo "Oracle"
        ;;
    db2)
        echo "IBM DB2"
        ;;
    syb)
        echo "SAP ASE (Sybase)"
        ;;
    ada)
        echo "MaxDB"
        ;;
    sap)
        echo "MaxDB"
        ;;
    *)
        echo "Unknown"
        ;;
    esac
}
# Does not work well with HANA databases
function_db_status(){   
    if [ "$db_systems_found" -eq 0 ]; then
        echo "No database instances found."
    else
        local db_name="${1^^}"
        if [[ -z "$db_name" || "$db_name" = "ALL" || "$db_name" = "NONE" ]]; then
            for i in "${db_systems_array[@]}"; do
                function_db_status $i
            done
        elif [[ ${#db_name} -ne 3 && ! "$db_name" == *"@"* ]]; then
                echo "! Error: Database name not having exactly 3 characters"
                return 1
        else
            local db_type
            echo "=== Checking status for database: $db_name"
            if ! db_type=$(function_db_type $db_name); then
                echo "! Error: Unable to determine database type for $db_name"
                return 1
            else
                result_all=$(/usr/sap/hostctrl/exe/saphostctrl -function GetDatabaseStatus -dbname $db_name -dbtype $db_type )
                result_short=$(echo "$result_all" |head -1|awk '{ print $3 }')
                if [ ! $? -eq 0 ]; then
                    echo "! Error executing command"
                    return 1
                else
                    echo "Database Type: $(db_type_friendly_name "$db_type")"
                    echo "$result_all - $db_name"
                fi
            fi
        fi
    fi
}
function_db_stop(){
    local db_stop_exit_status=0
    local db_name="${1^^}"
    local db_type
    if [ "$db_systems_found" -eq 0 ]; then
        echo "No database instances found to stop."
    else
        if [[ "$db_name" = "ALL" ]]; then      
            local db_status
            for sid in "${db_systems_array[@]}"; do
                if ! db_status=$(function_db_status $sid); then
                    echo "No database associated with instance $sid or it is a HANA database which will be stopped as an instance. Skipping"
                else
                    if ! db_type=$(function_db_type "$sid"); then
                        echo "! Error: Unable to determine database type for $sid"
                        db_stop_exit_status=1
                    else
                        echo "=== Stopping database associated with instance $sid..."
                        echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $sid -dbtype $db_type"
                        if [[ $testexec -eq 0 ]]; then
                            /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $sid -dbtype $db_type
                        else
                            echo "[TEST MODE] /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $sid -dbtype $db_type"
                        fi
                        /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $sid -dbtype $db_type
                        if [ $? -eq 0 ]; then
                            echo "=== Database associated with instance $sid stopped successfully." 
                        else
                            echo "! Error: Failed to stop database associated with instance $sid. Trying with force option..."
                            echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $sid -dbtype $db_type -force"
                            if [[ $testexec -eq 0 ]]; then
                                /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $sid -dbtype $db_type -force
                            else
                                echo "[TEST MODE] /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $sid -dbtype $db_type -force"
                            fi
                            /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $sid -dbtype $db_type -force
                            if [ $? -eq 0 ]; then
                                echo "=== Database associated with instance $sid stopped successfully with force option."
                            else
                                echo "! Error: Failed to stop database associated with instance $sid even with force option."
                                db_stop_exit_status=1
                            fi
                        fi
                    fi
                fi
            done
        else
            if ! db_type=$(function_db_type "$db_name"); then
                echo "! Error: Unable to determine database type for $db_name"
                db_stop_exit_status=1
            else
                echo "=== Stopping database $db_name of type $db_type..."
                echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $db_name -dbtype $db_type"
                if [[ $testexec -eq 0 ]]; then
                    /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $db_name -dbtype $db_type
                else
                    echo "[TEST MODE] /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $db_name -dbtype $db_type"
                fi
                
                if [ $? -eq 0 ]; then
                    echo "=== Database $db_name stopped successfully."
                else
                    echo "=== Failed to stop database $db_name. Trying with force option..."
                    echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $db_name -dbtype $db_type -force"
                    if [[ $testexec -eq 0 ]]; then
                        /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $db_name -dbtype $db_type -force
                    else
                        echo "[TEST MODE] /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $db_name -dbtype $db_type -force"
                    fi
                    if [ $? -eq 0 ]; then
                        echo "=== Database $db_name stopped successfully with force option."
                    else
                        echo "! Error: Failed to stop database $db_name even with force option."
                        db_stop_exit_status=1
                    fi
                fi
            fi
        fi
    fi
    return $db_stop_exit_status
}
function_db_start(){
    local db_start_exit_status=0
    local db_name="${1^^}"
    local db_type
    if [ "$db_systems_found" -eq 0 ]; then
        echo "No database instances found to start."
    else
        if [[ "$db_name" = "ALL" ]]; then      
            local db_status
            for sid in "${db_systems_array[@]}"; do
                if ! db_status=$(function_db_status $sid); then
                    echo "No database associated with instance $sid or it is a HANA database which will be started as an instance. Skipping"
                else
                    if ! db_type=$(function_db_type "$sid"); then
                        echo "! Error: Unable to determine database type for $sid"
                        db_start_exit_status=1
                    else
                        echo "=== Starting database associated with instance $sid..."
                        echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $sid -dbtype $db_type"
                        if [[ $testexec -eq 0 ]]; then
                            /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $sid -dbtype $db_type 
                        else
                            echo "[TEST MODE] /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $sid -dbtype $db_type"
                        fi  
                        if [ $? -eq 0 ]; then
                            echo "=== Database associated with instance $sid started successfully." 
                        else
                            echo "! Warning: Failed to start database associated with instance $sid. Trying with force option..."
                            echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $sid -dbtype $db_type -force"
                            if [[ $testexec -eq 0 ]]; then
                                /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $sid -dbtype $db_type -force
                            else
                                echo "[TEST MODE] /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $sid -dbtype $db_type -force"
                            fi
                            if [ $? -eq 0 ]; then
                                echo "=== Database associated with instance $sid started successfully with force option."
                            else
                                echo "! Error: Failed to start database associated with instance $sid even with force option."
                                db_start_exit_status=1
                            fi
                        fi
                    fi
                fi
            done
        else
            if ! db_type=$(function_db_type "$db_name"); then
                echo "! Error: Unable to determine database type for $db_name"
                db_start_exit_status=1
            else
                echo "=== Starting database $db_name of type $db_type..."
                echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $db_name -dbtype $db_type"
                if [[ $testexec -eq 0 ]]; then
                    /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $db_name -dbtype $db_type
                else
                    echo "[TEST MODE] /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $db_name -dbtype $db_type"
                fi
                if [ $? -eq 0 ]; then
                    echo "=== Database $db_name started successfully."
                else
                    echo "! Warning: Failed to start database $db_name. Trying with force option..."
                    echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $db_name -dbtype $db_type -force"
                    if [[ $testexec -eq 0 ]]; then
                        /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $db_name -dbtype $db_type -force
                    else
                        echo "[TEST MODE] /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $db_name -dbtype $db_type -force"
                    fi                   
                    if [ $? -eq 0 ]; then
                        echo "=== Database $db_name started successfully with force option."
                    else
                        echo "! Error: Failed to start database $db_name even with force option."
                        db_start_exit_status=1
                    fi
                fi
            fi
        fi
    fi
    return $db_start_exit_status
}
function_db_restart(){
    if [ "$db_systems_found" -eq 0 ]; then
        echo "No database instances found to start."
    else
        local db_name="${1^^}"
        if ! function_db_stop $db_name; then
            return 1
        elif ! function_db_start $db_name; then
            return 1
        fi
    fi
}
# SAP INSTANCE FUNCTIONS
function_instance_list(){
    local sap_instances_all_array=( "${sap_instances_array[@]}" "${sap_daa_instances_array[@]}" )
    if ! [ "$sap_instances_found" -eq 1 ]; then
        echo "No SAP instances found."
    else
        local length=${#sap_instances_all_array[@]}
        for (( i=0; i<(${length}); i+=5 ));
        do 
            function_list_in(){
                echo "${sap_instances_all_array[$i]} --> ${sap_instances_all_array[$i+1]}_${sap_instances_all_array[$i+2]}${sap_instances_all_array[$i+3]}_${sap_instances_all_array[$i+4]}"
            }
            if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then
                function_list_in
            else
                if [ "$1" = "${sap_instances_all_array[$i]}" ]; then
                    function_list_in
                fi
            fi
        done
    fi
}
function_instance_status(){
    local instance_status_exit_status=0
    if ! [ "$sap_instances_found" -eq 1 ]; then
        echo "No SAP instances found."
        return $instance_status_exit_status
    fi

    local sap_instances_all_array_length=${#sap_instances_all_array[@]}

    # use local loop index to avoid clobbering caller's variables
    local idx
    local result

    # If no argument or "all"/"None", show status for all instances
    if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then
        for (( idx=0; idx<sap_instances_all_array_length; idx+=5 )); do 
            local sid_lower=${sap_instances_all_array[$idx],,}
            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_all_array[$idx+3]} -function GetProcessList" >> /dev/null
            result="$?"
            # Check the result and output accordingly
            if [[ "$result" = "4"  ]]; then
                echo "STOPPED - ${sap_instances_all_array[$idx]} --> ${sap_instances_all_array[$idx+1]}_${sap_instances_all_array[$idx+2]}${sap_instances_all_array[$idx+3]}_${sap_instances_all_array[$idx+4]}" 
                overall_exit_status=1
            elif [[ "$result" = "2" || "$result" = "0"  ]]; then
                echo "PARTIALLY RUNNING - ${sap_instances_all_array[$idx]} --> ${sap_instances_all_array[$idx+1]}_${sap_instances_all_array[$idx+2]}${sap_instances_all_array[$idx+3]}_${sap_instances_all_array[$idx+4]}" 
                overall_exit_status=1
            elif  [[ "$result" = "3" ]]; then 
                echo "RUNNING - ${sap_instances_all_array[$idx]} --> ${sap_instances_all_array[$idx+1]}_${sap_instances_all_array[$idx+2]}${sap_instances_all_array[$idx+3]}_${sap_instances_all_array[$idx+4]}"  
            fi
        done
    # Otherwise, show status for the specific SID
    elif [[ ${#1} -ne 3 ]]; then
        echo "! Error: Instance SID '$1' does not have exactly 3 characters"
        return 1
    else
        local instance_found=0
        # echo "Entering this loops for sid: $1"
        for (( idx=0; idx<sap_instances_all_array_length; idx+=5 )); do
            # echo "in the for loop checking instance: ${sap_instances_all_array[$idx]} for sid $1"
            if [ "$1" = "${sap_instances_all_array[$idx]}" ]; then
                # echo "Inside if loop for instance: ${sap_instances_all_array[$idx]} for sid $1"
                instance_found=1
                local sid_lower=${sap_instances_all_array[$idx],,}
                su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_all_array[$idx+3]} -function GetProcessList" >> /dev/null
                result="$?"
                # Check the result and output accordingly
                if [[ "$result" = "4"  ]]; then
                    echo "STOPPED - ${sap_instances_all_array[$idx]} --> ${sap_instances_all_array[$idx+1]}_${sap_instances_all_array[$idx+2]}${sap_instances_all_array[$idx+3]}_${sap_instances_all_array[$idx+4]}" 
                    instance_status_exit_status=1
                elif [[ "$result" = "2" || "$result" = "0"  ]]; then
                    echo "PARTIALLY RUNNING - ${sap_instances_all_array[$idx]} --> ${sap_instances_all_array[$idx+1]}_${sap_instances_all_array[$idx+2]}${sap_instances_all_array[$idx+3]}_${sap_instances_all_array[$idx+4]}" 
                    instance_status_exit_status=1
                elif  [[ "$result" = "3" ]]; then 
                    echo "RUNNING - ${sap_instances_all_array[$idx]} --> ${sap_instances_all_array[$idx+1]}_${sap_instances_all_array[$idx+2]}${sap_instances_all_array[$idx+3]}_${sap_instances_all_array[$idx+4]}"  
                fi
            fi
        done
        if [ "$instance_found" = "0" ]; then
            echo "! Error: Instance SID '$1' not found"
            return 1
        fi
    fi
    return $instance_status_exit_status
}
function_instance_status_det(){
    local overall_exit_status=0
    local length=${#sap_instances_all_array[@]}
    # echo "Array length: $length"
    for (( i=0; i<(${length}); i+=5 ));
    do 
        if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then
            local sid_lower=${sap_instances_all_array[$i],,}
            echo -e "${sap_instances_all_array[$i]} --> ${sap_instances_all_array[$i+1]}_${sap_instances_all_array[$i+2]}${sap_instances_all_array[$i+3]}_${sap_instances_all_array[$i+4]}"
            case ${sap_instances_all_array[$i+2]} in
            D)
                echo "Instance Type: ${sap_instances_all_array[$i+2]} - Dialog Instance"
                ;;
            DVEBMGS)
                echo "Instance Type: ${sap_instances_all_array[$i+2]} - Central Instance"
                ;;
            ASCS)
                echo "Instance Type: ${sap_instances_all_array[$i+2]} - ABAP Central Services Instance"
                ;;
            SCS)
                echo "Instance Type: ${sap_instances_all_array[$i+2]} - JAVA Central Services Instance"
                ;;
            J)
                echo "Instance Type: ${sap_instances_all_array[$i+2]} - JAVA Instance"
                ;;
            C)
                echo "Instance Type: ${sap_instances_all_array[$i+2]} - Content Server"
                ;;
            SMDA)
                echo "Instance Type: ${sap_instances_all_array[$i+2]} - Solution Manager Diagnostics Instance"
                ;;
            HDB)
                echo "Instance Type: ${sap_instances_all_array[$i+2]} - HANA Platform Instance"
                ;;
            esac
            # echo "Instance: ${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}"
            # echo "Hostname: ${sap_instances_all_array[$i+4]}"
            # echo "SAP Instance: ${sap_instances_all_array[$i]}_${sap_instances_all_array[$i+1]}${sap_instances_all_array[$i+2]}_${sap_instances_all_array[$i+3]}"
            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_all_array[$i+3]} -function GetProcessList"
            if ! [ $? -eq 3 ]; then
                overall_exit_status=1
            fi
        else
            if [ "$1" = "${sap_instances_all_array[$i]}" ]; then
                local sid_lower=${sap_instances_all_array[$i],,}
                su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_all_array[$i+3]} -function GetProcessList" >> /dev/null
                echo -e "${sap_instances_all_array[$i]} --> ${sap_instances_all_array[$i+1]}_${sap_instances_all_array[$i+2]}${sap_instances_all_array[$i+3]}_${sap_instances_all_array[$i+4]}"
                case ${sap_instances_all_array[$i+2]} in
                D)
                    echo "Instance Type: ${sap_instances_all_array[$i+2]} - Dialog Instance"
                    ;;
                DVEBMGS)
                    echo "Instance Type: ${sap_instances_all_array[$i+2]} - Central Instance"
                    ;;
                ASCS)
                    echo "Instance Type: ${sap_instances_all_array[$i+2]} - ABAP Central Services Instance"
                    ;;
                SCS)
                    echo "Instance Type: ${sap_instances_all_array[$i+2]} - JAVA Central Services Instance"
                    ;;
                J)
                    echo "Instance Type: ${sap_instances_all_array[$i+2]} - JAVA Instance"
                    ;;
                SMDA)
                    echo "Instance Type: ${sap_instances_all_array[$i+2]} - Solution Manager Diagnostics Instance"
                    ;;
                HDB)
                    echo "Instance Type: ${sap_instances_all_array[$i+2]} - HANA Platform Instance"
                    ;;
                esac
                # echo "Instance: ${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}"
                # echo "Hostname: ${sap_instances_all_array[$i+4]}"
                # echo "SAP Instance: ${sap_instances_all_array[$i]}_${sap_instances_all_array[$i+1]}${sap_instances_all_array[$i+2]}_${sap_instances_all_array[$i+3]}"
                su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_all_array[$i+3]} -function GetProcessList"
                if ! [ $? -eq 3 ]; then
                    overall_exit_status=1
                fi
                echo ""=====================================================""          
            fi
        fi
    done
    return $overall_exit_status
}
function_instance_version(){
    if ! [ "$sap_instances_found" -eq 1 ]; then
        echo "No SAP instances found."
    else
        local length=${#sap_instances_all_array[@]}
        local instance_found=0
        for (( i=0; i<(${length}); i+=5 ));
        do 
            if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then
                instance_found=1
                echo -e "${sap_instances_all_array[$i]} --> ${sap_instances_all_array[$i+1]}_${sap_instances_all_array[$i+2]}${sap_instances_all_array[$i+3]}_${sap_instances_all_array[$i+4]}"
                local sid_lower=${sap_instances_all_array[$i],,}
                su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_all_array[$i+3]} -function GetVersionInfo"           
                echo "=================================="
            else
                if [ "$1" = "${sap_instances_all_array[$i]}" ]; then
                    echo -e "${sap_instances_all_array[$i]} --> ${sap_instances_all_array[$i+1]}_${sap_instances_all_array[$i+2]}${sap_instances_all_array[$i+3]}_${sap_instances_all_array[$i+4]}"
                    local sid_lower=${sap_instances_all_array[$i],,}
                    instance_found=1
                    su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_all_array[$i+3]} -function GetVersionInfo"          
                    echo "=================================="
                fi
            fi
        done
        if [ "$instance_found" = "0" ]; then
            echo "Instance $1 not found"
        fi
    fi
}
# Checks status of SAP Systems as a whole without checking individual instances or databases
function_cleanipc(){
    echo "Cleaning Shared Memory/semaphores..."
    echo "Command: cleanipc $1 remove"
    if [[ $testexec -eq 0 ]]; then
        cleanipc $1 remove
    else
        echo "[TEST MODE]  cleanipc $1 remove"
    fi
    if [ $? -ne 0 ]; then
        echo "! Error cleaning Shared Memory/semaphores for system $1"
        return 1
    fi
}
function_system_status(){
    local s_idx
    if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then
        local sap_systems_length=${#sap_systems_array[@]}
        for (( s_idx=0; s_idx<(${sap_systems_length}); s_idx+=1 )); do 
            local s_sid=${sap_systems_array[$s_idx]}
            echo "=== Checking status for SAP system: $s_sid"
            function_instance_status "$s_sid" || true
        done 
    else
        echo "=== Checking status for SAP system: $1"
        function_instance_status "$1" || true
    fi
}
# Stops SAP Systems as a whole without stopping individual instances or databases
function_system_stop(){
    if ! [ "$sap_systems_found" -eq 1 ]; then
        echo "No SAP Systems found."
    else
        local sap_abap_systems_length=${#sap_abap_systems_array[@]}
        local sap_java_systems_length=${#sap_java_systems_array[@]}
        local sap_hdb_systems_length=${#sap_hdb_systems_array[@]}
        local sap_contentserver_systems_length=${#sap_contentserver_systems_array[@]}
        
        local sap_instances_length=${#sap_instances_array[@]}
        local sap_scs_instances_length=${#sap_scs_instances_array[@]}
        local sap_ascs_instances_length=${#sap_ascs_instances_array[@]}
        local sap_java_instances_length=${#sap_java_instances_array[@]}
        local sap_abap_instances_length=${#sap_abap_instances_array[@]}
        local sap_hdb_instances_length=${#sap_hdb_instances_array[@]}
        local sap_contentserver_instances_length=${#sap_contentserver_instances_array[@]}

        if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then         
            # Stop JAVA systems first
            for (( i=0; i<(${sap_java_systems_length}); i+=1 )); do 
                local sid_lower=${sap_java_systems_array[$i],,}                                   
                local sys_num=""
                # Stop JAVA instances first
                for (( j=0; j<(${sap_java_instances_length}); j+=5 )); do 
                    if [[ "${sap_java_systems_array[$i]}" == "${sap_java_instances_array[$j]}" ]]; then
                        echo "Processing JAVA system: ${sap_java_systems_array[$i]}"
                        sys_num=${sap_java_instances_array[$j+3]}
                        local instance_type=$(function_instance_type "${sap_java_instances_array[$j+2]}")
                        echo "Stopping $instance_type ==> ${sap_java_systems_array[$i]} -> ${sap_java_instances_array[$j+1]}_${sap_java_instances_array[$j+2]}${sap_java_instances_array[$j+3]}_${sap_java_instances_array[$j+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error stopping $instance_type: ${sap_java_instances_array[$i]} --> ${sap_java_instances_array[$i+1]}_${sap_java_instances_array[$i+2]}${sap_java_instances_array[$i+3]}_${sap_java_instances_array[$i+4]}"
                            return 1
                        fi
                        function_cleanipc "${sys_num}"
                    fi
                done
                # Stop SCS instances next
                for (( j=0; j<(${sap_scs_instances_length}); j+=5 )); do 
                    if [[ "${sap_java_systems_array[$i]}" == "${sap_scs_instances_array[$j]}" ]]; then
                        # echo "Found instance $j for system ${sap_systems_array[$i]}"
                        sys_num=${sap_scs_instances_array[$j+3]}
                        local instance_type=$(function_instance_type "${sap_scs_instances_array[$j+2]}")
                        echo "Stopping $instance_type ==> ${sap_java_systems_array[$i]} -> ${sap_scs_instances_array[$j+1]}_${sap_scs_instances_array[$j+2]}${sap_scs_instances_array[$j+3]}_${sap_scs_instances_array[$j+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error stopping $instance_type: ${sap_scs_instances_array[$i]} --> ${sap_scs_instances_array[$i+1]}_${sap_scs_instances_array[$i+2]}${sap_scs_instances_array[$i+3]}_${sap_scs_instances_array[$i+4]}"
                            return 1
                        fi
                        function_cleanipc "${sys_num}"       
                    fi
                done
            done
            # Then stop non-JAVA systems
            for (( i=0; i<(${sap_abap_systems_length}); i+=1 )); do
                local sid_lower=${sap_abap_systems_array[$i],,}                                   
                local sys_num=""
                
                # Stop ABAP Dialog instances first
                for (( j=0; j<(${sap_abap_instances_length}); j+=5 )); do
                    if [[ "${sap_abap_systems_array[$i]}" == "${sap_abap_instances_array[$j]}" ]]; then
                        echo "Processing ABAP system: ${sap_abap_systems_array[$i]}"
                        sys_num=${sap_abap_instances_array[$j+3]}
                        local instance_type=$(function_instance_type "${sap_abap_instances_array[$j+2]}")
                        echo "Stopping $instance_type ==> ${sap_abap_systems_array[$i]} -> ${sap_abap_instances_array[$j+1]}_${sap_abap_instances_array[$j+2]}${sap_abap_instances_array[$j+3]}_${sap_abap_instances_array[$j+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error stopping $instance_type: ${sap_abap_instances_array[$i]} --> ${sap_abap_instances_array[$i+1]}_${sap_abap_instances_array[$i+2]}${sap_abap_instances_array[$i+3]}_${sap_abap_instances_array[$i+4]}"
                            return 1
                        fi  
                        function_cleanipc "${sys_num}"      
                    fi
                done
                # Stop ASCS instances next
                for (( j=0; j<(${sap_ascs_instances_length}); j+=5 )); do 
                    if [[ "${sap_abap_systems_array[$i]}" == "${sap_ascs_instances_array[$j]}" ]]; then
                        sys_num=${sap_ascs_instances_array[$j+3]}
                        local instance_type=$(function_instance_type "${sap_ascs_instances_array[$j+2]}")
                        # echo "System number: $sys_num"
                        echo "Stopping $instance_type ==> ${sap_abap_systems_array[$i]} -> ${sap_ascs_instances_array[$j+1]}_${sap_ascs_instances_array[$j+2]}${sap_ascs_instances_array[$j+3]}_${sap_ascs_instances_array[$j+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error stopping $instance_type: ${sap_ascs_instances_array[$i]} --> ${sap_ascs_instances_array[$i+1]}_${sap_ascs_instances_array[$i+2]}${sap_ascs_instances_array[$i+3]}_${sap_ascs_instances_array[$i+4]}"
                            return 1
                        fi
                        function_cleanipc "${sys_num}"       
                    fi
                done
            done
            # Then, stop Content Servers      
            for (( i=0; i<(${sap_contentserver_systems_length}); i+=1 )); do 
                local sid_lower=${sap_contentserver_systems_array[$i],,}                                   
                local sys_num=""
                echo "Processing Content Server system: ${sap_contentserver_systems_array[$i]}"
                for (( j=0; j<(${sap_contentserver_instances_length}); j+=5 )); do 
                    if [[ "${sap_contentserver_systems_array[$i]}" == "${sap_contentserver_instances_array[$j]}" ]]; then
                        sys_num=${sap_contentserver_instances_array[$j+3]}
                        local instance_type=$(function_instance_type "${sap_contentserver_instances_array[$j+2]}")
                        echo "Stopping $instance_type ==> ${sap_contentserver_systems_array[$i]} -> ${sap_contentserver_instances_array[$j+1]}_${sap_contentserver_instances_array[$j+2]}${sap_contentserver_instances_array[$j+3]}_${sap_contentserver_instances_array[$j+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error stopping $instance_type: ${sap_contentserver_instances_array[$i]} --> ${sap_contentserver_instances_array[$i+1]}_${sap_contentserver_instances_array[$i+2]}${sap_contentserver_instances_array[$i+3]}_${sap_contentserver_instances_array[$i+4]}"
                            return 1
                        fi
                        function_cleanipc "${sys_num}" 
                    fi
                done
            done
            # Then, stop HDB systems if any
            for (( i=0; i<(${sap_hdb_systems_length}); i+=1 )); do 
                local sid_lower=${sap_hdb_systems_array[$i],,}                                   
                local sys_num=""
                echo "Processing HDB system: ${sap_hdb_systems_array[$i]}"
                for (( j=0; j<(${sap_hdb_instances_length}); j+=5 )); do 
                    if [[ "${sap_hdb_systems_array[$i]}" == "${sap_hdb_instances_array[$j]}" ]]; then
                        sys_num=${sap_hdb_instances_array[$j+3]}
                        local instance_type=$(function_instance_type "${sap_hdb_instances_array[$j+2]}")
                        echo "Stopping $instance_type ==> ${sap_hdb_instances_array[$i]} --> ${sap_hdb_instances_array[$i+1]}_${sap_hdb_instances_array[$i+2]}${sap_hdb_instances_array[$i+3]}_${sap_hdb_instances_array[$i+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error stopping $instance_type: ${sap_hdb_instances_array[$i]} --> ${sap_hdb_instances_array[$i+1]}_${sap_hdb_instances_array[$i+2]}${sap_hdb_instances_array[$i+3]}_${sap_hdb_instances_array[$i+4]}"
                            return 1
                        fi
                        function_cleanipc "${sys_num}"           
                    fi
                done
            done
        else
            
            local sid_lower=${1,,}
            local sys_num=""
            for (( i=0; i<(${sap_java_instances_length}); i+=5 )); do 
                if [[ "${sap_java_instances_array[$i]}" == "$1" ]]; then
                        echo "Processing SAP system ==> $1"
                        sys_num=${sap_java_instances_array[$i+3]}
                        local instance_type=$(function_instance_type "${sap_java_instances_array[$i+2]}")
                        echo "Stopping $instance_type ==> $1 --> ${sap_java_instances_array[$i+1]}_${sap_java_instances_array[$i+2]}${sap_java_instances_array[$i+3]}_${sap_java_instances_array[$i+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error stopping $instance_type: ${sap_java_instances_array[$i]} --> ${sap_java_instances_array[$i+1]}_${sap_java_instances_array[$i+2]}${sap_java_instances_array[$i+3]}_${sap_java_instances_array[$i+4]}"
                            return 1
                        fi
                        function_cleanipc "${sys_num}"
                fi
            done
            for (( i=0; i<(${sap_abap_instances_length}); i+=5 )); do 
                if [[ "${sap_abap_instances_array[$i]}" == "$1" ]]; then
                        echo "Processing SAP system ==> $1"
                        sys_num=${sap_abap_instances_array[$i+3]}
                        local instance_type=$(function_instance_type "${sap_abap_instances_array[$i+2]}")
                        echo "Stopping $instance_type ==> $1 --> ${sap_abap_instances_array[$i+1]}_${sap_abap_instances_array[$i+2]}${sap_abap_instances_array[$i+3]}_${sap_abap_instances_array[$i+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error stopping $instance_type: ${sap_abap_instances_array[$i]} --> ${sap_abap_instances_array[$i+1]}_${sap_abap_instances_array[$i+2]}${sap_abap_instances_array[$i+3]}_${sap_abap_instances_array[$i+4]}"
                            return 1
                        fi
                        function_cleanipc "${sys_num}"       
                fi
            done
            for (( i=0; i<(${sap_instances_length}); i+=5 )); do 
                if [[ "${sap_instances_array[$i]}" == "$1" ]]; then
                    sys_num=${sap_instances_array[$i+3]}
                    if [[ "${sap_instances_array[$i+2]}" != D* && "${sap_instances_array[$i+2]}" != "J" ]]; then
                        echo "Processing SAP system ==> $1"
                        local instance_type=$(function_instance_type "${sap_instances_array[$i+2]}")
                        echo "Stopping $instance_type instance ==> $1 --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error stopping $instance_type: ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                            return 1
                        fi
                        function_cleanipc "${sys_num}"           
                    fi
                fi
            done
        fi
    fi

}
# Starts SAP Systems as a whole without starting individual instances or databases
function_system_start(){
    if ! [ "$sap_systems_found" -eq 1 ]; then
        echo "No SAP Systems found."
    else
        local sap_abap_systems_length=${#sap_abap_systems_array[@]}
        local sap_java_systems_length=${#sap_java_systems_array[@]}
        local sap_hdb_systems_length=${#sap_hdb_systems_array[@]}
        local sap_contentserver_systems_length=${#sap_contentserver_systems_array[@]}
        
        local sap_instances_length=${#sap_instances_array[@]}
        local sap_scs_instances_length=${#sap_scs_instances_array[@]}
        local sap_ascs_instances_length=${#sap_ascs_instances_array[@]}
        local sap_java_instances_length=${#sap_java_instances_array[@]}
        local sap_abap_instances_length=${#sap_abap_instances_array[@]}
        local sap_hdb_instances_length=${#sap_hdb_instances_array[@]}
        local sap_contentserver_instances_length=${#sap_contentserver_instances_array[@]}

        if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then         
            # Start HDB systems
            for (( i=0; i<(${sap_hdb_systems_length}); i+=1 )); do 
                local sid_lower=${sap_hdb_systems_array[$i],,}                                   
                local sys_num=""
                echo "Processing HDB system: ${sap_hdb_systems_array[$i]}"
                for (( j=0; j<(${sap_hdb_instances_length}); j+=5 )); do 
                    if [[ "${sap_hdb_systems_array[$i]}" == "${sap_hdb_instances_array[$j]}" ]]; then
                        sys_num=${sap_hdb_instances_array[$j+3]}
                        local instance_type=$(function_instance_type "${sap_hdb_instances_array[$j+2]}")
                        echo "Starting $instance_type ==> ${sap_hdb_instances_array[$i]} --> ${sap_hdb_instances_array[$i+1]}_${sap_hdb_instances_array[$i+2]}${sap_hdb_instances_array[$i+3]}_${sap_hdb_instances_array[$i+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error starting $instance_type: ${sap_hdb_instances_array[$i]} --> ${sap_hdb_instances_array[$i+1]}_${sap_hdb_instances_array[$i+2]}${sap_hdb_instances_array[$i+3]}_${sap_hdb_instances_array[$i+4]}"
                            return 1
                        fi           
                    fi
                done
            done
            # Then start non-JAVA systems
            for (( i=0; i<(${sap_abap_systems_length}); i+=1 )); do
                local sid_lower=${sap_abap_systems_array[$i],,}                                   
                local sys_num=""
                echo "Processing ABAP system: ${sap_abap_systems_array[$i]}"
                # Start ASCS instances
                for (( j=0; j<(${sap_ascs_instances_length}); j+=5 )); do 
                    if [[ "${sap_abap_systems_array[$i]}" == "${sap_ascs_instances_array[$j]}" ]]; then
                        sys_num=${sap_ascs_instances_array[$j+3]}
                        local instance_type=$(function_instance_type "${sap_ascs_instances_array[$j+2]}")
                        # echo "System number: $sys_num"
                        echo "Starting $instance_type ==> ${sap_abap_systems_array[$i]} -> ${sap_ascs_instances_array[$j+1]}_${sap_ascs_instances_array[$j+2]}${sap_ascs_instances_array[$j+3]}_${sap_ascs_instances_array[$j+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error starting $instance_type: ${sap_ascs_instances_array[$i]} --> ${sap_ascs_instances_array[$i+1]}_${sap_ascs_instances_array[$i+2]}${sap_ascs_instances_array[$i+3]}_${sap_ascs_instances_array[$i+4]}"
                            return 1
                        fi       
                    fi
                done
                # Start ABAP Dialog instances
                for (( j=0; j<(${sap_abap_instances_length}); j+=5 )); do
                    if [[ "${sap_abap_systems_array[$i]}" == "${sap_abap_instances_array[$j]}" ]]; then
                        sys_num=${sap_abap_instances_array[$j+3]}
                        local instance_type=$(function_instance_type "${sap_abap_instances_array[$j+2]}")
                        echo "Starting $instance_type ==> ${sap_abap_systems_array[$i]} -> ${sap_abap_instances_array[$j+1]}_${sap_abap_instances_array[$j+2]}${sap_abap_instances_array[$j+3]}_${sap_abap_instances_array[$j+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error starting $instance_type: ${sap_abap_instances_array[$i]} --> ${sap_abap_instances_array[$i+1]}_${sap_abap_instances_array[$i+2]}${sap_abap_instances_array[$i+3]}_${sap_abap_instances_array[$i+4]}"
                            return 1
                        fi        
                    fi
                done
            done
            # Start JAVA systems
            for (( i=0; i<(${sap_java_systems_length}); i+=1 )); do 
                local sid_lower=${sap_java_systems_array[$i],,}                                   
                local sys_num=""
                echo "Processing JAVA system: ${sap_java_systems_array[$i]}"
                # Start SCS instances
                for (( j=0; j<(${sap_scs_instances_length}); j+=5 )); do 
                    if [[ "${sap_java_systems_array[$i]}" == "${sap_scs_instances_array[$j]}" ]]; then
                        # echo "Found instance $j for system ${sap_systems_array[$i]}"
                        sys_num=${sap_scs_instances_array[$j+3]}
                        local instance_type=$(function_instance_type "${sap_scs_instances_array[$j+2]}")
                        echo "Starting $instance_type ==> ${sap_java_systems_array[$i]} -> ${sap_scs_instances_array[$j+1]}_${sap_scs_instances_array[$j+2]}${sap_scs_instances_array[$j+3]}_${sap_scs_instances_array[$j+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error starting $instance_type: ${sap_scs_instances_array[$i]} --> ${sap_scs_instances_array[$i+1]}_${sap_scs_instances_array[$i+2]}${sap_scs_instances_array[$i+3]}_${sap_scs_instances_array[$i+4]}"
                            return 1
                        fi       
                    fi
                done
                # Start JAVA instances
                for (( j=0; j<(${sap_java_instances_length}); j+=5 )); do 
                    if [[ "${sap_java_systems_array[$i]}" == "${sap_java_instances_array[$j]}" ]]; then
                        sys_num=${sap_java_instances_array[$j+3]}
                        local instance_type=$(function_instance_type "${sap_java_instances_array[$j+2]}")
                        echo "Starting $instance_type ==> ${sap_java_systems_array[$i]} -> ${sap_java_instances_array[$j+1]}_${sap_java_instances_array[$j+2]}${sap_java_instances_array[$j+3]}_${sap_java_instances_array[$j+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error starting $instance_type: ${sap_java_instances_array[$i]} --> ${sap_java_instances_array[$i+1]}_${sap_java_instances_array[$i+2]}${sap_java_instances_array[$i+3]}_${sap_java_instances_array[$i+4]}"
                            return 1
                        fi       
                    fi
                done

            done
            # Start Content Servers      
            for (( i=0; i<(${sap_contentserver_systems_length}); i+=1 )); do 
                local sid_lower=${sap_contentserver_systems_array[$i],,}                                   
                local sys_num=""
                echo "Processing Content Server system: ${sap_contentserver_systems_array[$i]}"
                for (( j=0; j<(${sap_contentserver_instances_length}); j+=5 )); do 
                    if [[ "${sap_contentserver_systems_array[$i]}" == "${sap_contentserver_instances_array[$j]}" ]]; then
                        sys_num=${sap_contentserver_instances_array[$j+3]}
                        local instance_type=$(function_instance_type "${sap_contentserver_instances_array[$j+2]}")
                        echo "Starting $instance_type ==> ${sap_contentserver_systems_array[$i]} -> ${sap_contentserver_instances_array[$j+1]}_${sap_contentserver_instances_array[$j+2]}${sap_contentserver_instances_array[$j+3]}_${sap_contentserver_instances_array[$j+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error starting $instance_type: ${sap_contentserver_instances_array[$i]} --> ${sap_contentserver_instances_array[$i+1]}_${sap_contentserver_instances_array[$i+2]}${sap_contentserver_instances_array[$i+3]}_${sap_contentserver_instances_array[$i+4]}"
                            return 1
                        fi 
                    fi
                done
            done
        else
            echo "Processing SAP system ==> $1"
            local sid_lower=${1,,}
            local sys_num=""
            # Start HDB, Content Server, SCS and ASCS instances
            for (( i=0; i<(${sap_instances_length}); i+=5 )); do 
                if [[ "${sap_instances_array[$i]}" == "$1" ]]; then
                    sys_num=${sap_instances_array[$i+3]}
                    if [[ "${sap_instances_array[$i+2]}" != D* && "${sap_instances_array[$i+2]}" != "J" ]]; then
                        local instance_type=$(function_instance_type "${sap_instances_array[$i+2]}")
                        echo "Starting $instance_type instance ==> $1 --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error starting $instance_type: ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                            return 1
                        fi           
                    fi
                fi
            done
            # Start ABAP instances
            for (( i=0; i<(${sap_abap_instances_length}); i+=5 )); do 
                if [[ "${sap_abap_instances_array[$i]}" == "$1" ]]; then
                        sys_num=${sap_abap_instances_array[$i+3]}
                        local instance_type=$(function_instance_type "${sap_abap_instances_array[$i+2]}")
                        echo "Starting $instance_type ==> $1 --> ${sap_abap_instances_array[$i+1]}_${sap_abap_instances_array[$i+2]}${sap_abap_instances_array[$i+3]}_${sap_abap_instances_array[$i+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error starting $instance_type: ${sap_abap_instances_array[$i]} --> ${sap_abap_instances_array[$i+1]}_${sap_abap_instances_array[$i+2]}${sap_abap_instances_array[$i+3]}_${sap_abap_instances_array[$i+4]}"
                            return 1
                    fi         
                fi
            done
            # Start JAVA instances
            for (( i=0; i<(${sap_java_instances_length}); i+=5 )); do 
                if [[ "${sap_java_instances_array[$i]}" == "$1" ]]; then
                        sys_num=${sap_java_instances_array[$i+3]}
                        local instance_type=$(function_instance_type "${sap_java_instances_array[$i+2]}")
                        echo "Starting $instance_type ==> $1 --> ${sap_java_instances_array[$i+1]}_${sap_java_instances_array[$i+2]}${sap_java_instances_array[$i+3]}_${sap_java_instances_array[$i+4]}"
                        echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        if [[ $testexec -eq 0 ]]; then
                            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        else
                            echo "[TEST MODE] su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartWait 300 10"
                        fi
                        if [ $? -ne 0 ]; then
                            echo "! Error starting $instance_type: ${sap_java_instances_array[$i]} --> ${sap_java_instances_array[$i+1]}_${sap_java_instances_array[$i+2]}${sap_java_instances_array[$i+3]}_${sap_java_instances_array[$i+4]}"
                            return 1
                        fi
                fi
            done
        fi
    fi
}
# Restarts SAP Systems as a whole without restarting individual instances or databases
function_system_restart(){
    if ! [ "$sap_instances_found" -eq 1 ]; then
        echo "No SAP Systems found."
    else
        if ! function_system_stop $1; then
            echo "! Error: Failed to stop system $1. Aborting restart."
            return 1
        elif ! function_system_start $1; then
            echo "! Error: Failed to start system $1 after stopping."
            return 1
        fi
    fi
}
# Stops SAP Systems and associated non-hdb databases
function_all_stop(){
    if ! function_system_stop all; then
        echo "! Error stopping SAP systems."
        return 1
    elif ! function_db_stop all; then
        echo "! Error stopping databases."
        return 1
    fi
}
function_all_start(){
    if ! function_db_start all; then
        echo "! Error starting databases."
        return 1
    elif ! function_system_start all; then
        echo "Error starting SAP systems."
        return 1
    fi
}
function_all_restart(){
    if ! function_all_stop; then
        echo "! Error restarting all SAP systems and databases."
        return 1
    elif ! function_all_start; then
        echo "! Error restarting all SAP systems and databases."
        return 1
    fi
}
function_all_status(){
    local overall_exit_status=0
    if ! function_system_status $1; then
        overall_exit_status=1
    fi
    if ! function_db_status $1; then
        overall_exit_status=1
    fi
    return $overall_exit_status
}

## Main script logic
# Check if the number of arguments is correct
if [ "$#" -lt 1 ] || [ "$1" = "help" ]; then
    function_display_help
    exit 0
fi
# Find SAP and DB systems
function_find_sap_instances
function_find_db_systems
# Pendingn functions
# function_find_saprouters
# function_find_cloud_connectors

# Assign arguments to variables
command=$1
arg2=$2
arg3=$3
arg4=$4

# Validate arg1 and command
case $command in
    instance_list)
        function_instance_list $arg2
        ;;
    instance_status)
        function_instance_status $arg2
        ;;
    instance_status_det)
        function_instance_status_det $arg2
        ;;
    instance_version)
        function_instance_version $arg2
        ;;
    system_stop)
        if [[ -z "$arg2" ]]; then
            echo "! Error: 'option' is required for 'system_stop' command."
            function_display_help
            exit 1
        fi
        function_system_stop $arg2
        ;;
    system_start)
        if [[ -z "$arg2" ]]; then
            echo "! Error: 'option' is required for 'system_start' command."
            function_display_help
            exit 1
        fi
        function_system_start $arg2
        ;;
    system_restart)
        if [[ -z "$arg2" ]]; then   
            echo "! Error: 'option' is required for 'system_restart' command."
            function_display_help
            exit 1
        fi
        function_system_restart $arg2
        ;;
    system_status)
        function_system_status $arg2
        ;;
    db_list)
        function_db_list
        ;;
    db_status)
        function_db_status $arg2
        ;;
    db_stop)
        if [[ -z "$arg2" ]]; then
            echo "! Error: 'option' is required for 'db_stop' command."
            function_display_help
            exit 1
        fi
        function_db_stop $arg2
        ;;
    db_start)
        if [[ -z "$arg2" ]]; then
            echo "! Error: 'option' is required for 'db_start' command."
            function_display_help
            exit 1
        fi
        function_db_start $arg2
        ;;
    db_restart)
        if [[ -z "$arg2" ]]; then
            echo "! Error: 'option' is required for 'db_restart' command."
            function_display_help
            exit 1
        fi
        function_db_restart $arg2
        ;;
    db_type)
        function_db_type $arg2
        ;;
    all_stop)
       function_all_stop
        ;;
    all_start)
        function_all_start
        ;;
    all_restart)
        function_all_restart
        ;;
    all_status)
        function_all_status $arg2
        ;;
    # find_saprouter)
    #     function_find_saprouters
    #     ;;
    *)
        echo "! Error: 'command' must be 'instance_list', 'instance_status', 'instance_status_det', 'instance_version', 'system_status', 'system_stop', 'system_start', 'system_restart', 'db_status', 'db_stop', 'db_start', 'db_restart', 'db_type', 'all_stop', 'all_start' or 'all_restart'"
        function_display_help
        exit 1
        ;;
esac