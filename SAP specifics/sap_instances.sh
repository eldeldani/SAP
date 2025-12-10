#!/bin/bash
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


# DECLARE ARRAYS AND VARIABLES
## Includes all instances excluding SMD
declare -a sap_instances_array
# declare -a sap_java_instances_array
declare -a sap_daa_instances_array
declare -a sap_instances_all_array
# declare -a non_hdb_instances_array
# declare -a hdb_instances_array
declare -a db_systems_array
declare -a sap_systems_array
declare -a sap_abap_systems_array
declare -a sap_java_systems_array
declare -a sap_hdb_systems_array
declare -a sap_contentserver_systems_array
declare sap_instances_found=0
declare saprouter_instance_found=0
# declare non_hdb_instances_found=0
# declare hdb_instances_found=0
declare db_systems_found=0
declare sap_systems_found=0
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
                fi
                if [[ "$INSTANCE_TYPE" == D* ]]; then
                    sap_abap_instances_found=1
                    if ! [[ " ${sap_abap_systems_array[@]} " =~ " ${SID} " ]]; then
                        sap_abap_systems_array+=("$SID")
                    fi
                fi
                if [[ "$INSTANCE_TYPE" == "HDB" ]]; then
                    sap_hdb_instances_found=1
                    if ! [[ " ${sap_hdb_systems_array[@]} " =~ " ${SID} " ]]; then
                        sap_hdb_systems_array+=("$SID")
                    fi
                fi
                if [[ "$INSTANCE_TYPE" == "C" ]]; then
                    sap_contentserver_instances_found=1
                    if ! [[ " ${sap_contentserver_systems_array[@]} " =~ " ${SID} " ]]; then
                        sap_contentserver_systems_array+=("$SID")
                    fi
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
    echo "SAP ABAP systems found: ${sap_abap_systems_array[@]}"
    echo "SAP JAVA systems found: ${sap_java_systems_array[@]}"
    echo "SAP HDB systems found: ${sap_hdb_systems_array[@]}"
    echo "SAP Content Server systems found: ${sap_contentserver_systems_array[@]}"
    echo "SAP instances found: ${sap_instances_array[@]}"
    echo "SAP DAA instances found: ${sap_daa_instances_array[@]}"
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
                db_systems_array+=("$db_sid")
            done <<< "$db_list_output"
            db_systems_found=1
        fi
    fi
}
# DISPLAY HELP FUNCTION
function_display_help(){
    echo "Usage: $0 <command> [<option>]"
    echo "  <command> must be one of the following:"
    echo "  - instance_list: does not require an optional 'option' parameter, it could be instance SID or empty for all."
    echo "  - instance_status: does not require an optional 'option' if empty, will list status for all instances. If 'detail' is provided as 'option', detailed status will be shown. If instance SID is provided as 'option', status for that specific instance will be shown."
    echo "  - instance_version: does not require an optional 'option' if empty, will list version for all instances. If instance SID is provided as 'option', version for that specific instance will be shown."
    echo "  - instance_stop: requires an 'option' parameter (instance SID or 'all')."
    echo "  - instance_start: requires an 'option' parameter (instance SID or 'all')."
    echo "  - instance_restart: requires an 'option' parameter (instance SID or 'all')."
    echo "  - system_stop: requires an 'option' parameter (system SID or 'all')."
    echo "  - system_start: requires an 'option' parameter (system SID or 'all')."
    echo "  - db_list: does not require any parameters. Will list all database instances found on the host."
    echo "  - db_status does not require an optional 'option' parameter, it could be database name or empty for all."
    echo "  - db_stop requires an 'option' parameter (database name),"
    echo "  - db_start requires an 'option' parameter (database name),"
    echo "  - db_restart requires an 'option' parameter (database name),"
    echo "  - db_type requires an 'option' parameter (database name). Will return the database type for the given database name."
    echo "  - db_type can be: "
    echo "      hdb - SAP HANA Database"
    echo "      ora - Oracle Database"
    echo "      syb - SAP ASE (Sybase) Database"
    echo "      ada - MaxDB Database"
    echo "  - all_stop does not require any parameters. Will stop all SAP instances and associated databases on the host."
    echo "  - all_start does not require any parameters. Will start all SAP instances and associated databases on the host."
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
                elif [[ "$result_short" != "Running" ]]; then
                        echo "! Error: Database '$db_name' is not running. Current status: $result_short"
                        return 1
                else
                    echo "$result_all - $db_name"
                fi
            fi
        fi
    fi
}
function_db_stop(){
    local overall_exit_status=0
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
                        overall_exit_status=1
                    else
                        echo "=== Stopping database associated with instance $sid..."
                        echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $sid -dbtype $db_type"
                        # /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $sid -dbtype $db_type
                        if [ $? -eq 0 ]; then
                            echo "=== Database associated with instance $sid stopped successfully." 
                        else
                            echo "! Error: Failed to stop database associated with instance $sid. Trying with force option..."
                            # /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $sid -dbtype $db_type -force
                            if [ $? -eq 0 ]; then
                                echo "=== Database associated with instance $sid stopped successfully with force option."
                            else
                                echo "! Error: Failed to stop database associated with instance $sid even with force option."
                                overall_exit_status=1
                            fi
                        fi
                    fi
                fi
            done
        else
            if ! db_type=$(function_db_type "$db_name"); then
                echo "! Error: Unable to determine database type for $db_name"
                overall_exit_status=1
            else
                echo "=== Stopping database $db_name of type $db_type..."
                echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $db_name -dbtype $db_type"
                # /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $db_name -dbtype $db_type
                if [ $? -eq 0 ]; then
                    echo "=== Database $db_name stopped successfully."
                else
                    echo "=== Failed to stop database $db_name. Trying with force option..."
                    # /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $db_name -dbtype $db_type -force
                    if [ $? -eq 0 ]; then
                        echo "=== Database $db_name stopped successfully with force option."
                    else
                        echo "! Error: Failed to stop database $db_name even with force option."
                        overall_exit_status=1
                    fi
                fi
            fi
        fi
    fi
    return $overall_exit_status
}
function_db_start(){
    local overall_exit_status=0
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
                        overall_exit_status=1
                    else
                        echo "=== Starting database associated with instance $sid..."
                        echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $sid -dbtype $db_type"
                        # /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $sid -dbtype $db_type                     
                        if [ $? -eq 0 ]; then
                            echo "=== Database associated with instance $sid started successfully." 
                        else
                            echo "! Warning: Failed to start database associated with instance $sid. Trying with force option..."
                            # /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $sid -dbtype $db_type -force
                            if [ $? -eq 0 ]; then
                                echo "=== Database associated with instance $sid started successfully with force option."
                            else
                                echo "! Error: Failed to start database associated with instance $sid even with force option."
                                overall_exit_status=1
                            fi
                        fi
                    fi
                fi
            done
        else
            if ! db_type=$(function_db_type "$db_name"); then
                echo "! Error: Unable to determine database type for $db_name"
                overall_exit_status=1
            else
                echo "=== Starting database $db_name of type $db_type..."
                echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $db_name -dbtype $db_type"
                # /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $db_name -dbtype $db_type
                if [ $? -eq 0 ]; then
                    echo "=== Database $db_name started successfully."
                else
                    echo "! Warning: Failed to start database $db_name. Trying with force option..."
                    # /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $db_name -dbtype $db_type -force
                    if [ $? -eq 0 ]; then
                        echo "=== Database $db_name started successfully with force option."
                    else
                        echo "! Error: Failed to start database $db_name even with force option."
                        overall_exit_status=1
                    fi
                fi
            fi
        fi
    fi
    return $overall_exit_status
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
    local overall_exit_status=0
    if ! [ "$sap_instances_found" -eq 1 ]; then
        echo "No SAP instances found."
        return $overall_exit_status
    elif [[ -z "$1" || ${#1} -ne 3 ]]; then
        echo "! Error: Instance SID not supplied or not having exactly 3 characters"
        return 1
    else
        local length=${#sap_instances_all_array[@]}
        for (( i=0; i<(${length}); i+=5 ));
        do 
            if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then
                local sid_lower=${sap_instances_all_array[$i],,}
                su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_all_array[$i+3]} -function GetProcessList" >> /dev/null
                result="$?"
                # echo "Resultado ALL: "$result""
                # Check the result and output accordingly
                if [[ "$result" = "4"  ]]; then
                    echo "STOPPED - ${sap_instances_all_array[$i]} --> ${sap_instances_all_array[$i+1]}_${sap_instances_all_array[$i+2]}${sap_instances_all_array[$i+3]}_${sap_instances_all_array[$i+4]}" 
                    overall_exit_status=1
                elif [[ "$result" = "2" || "$result" = "0"  ]]; then
                    echo "PARTIALLY RUNNING - ${sap_instances_all_array[$i]} --> ${sap_instances_all_array[$i+1]}_${sap_instances_all_array[$i+2]}${sap_instances_all_array[$i+3]}_${sap_instances_all_array[$i+4]}" 
                    overall_exit_status=1
                elif  [[ "$result" = "3" ]]; then 
                    echo "RUNNING - ${sap_instances_all_array[$i]} --> ${sap_instances_all_array[$i+1]}_${sap_instances_all_array[$i+2]}${sap_instances_all_array[$i+3]}_${sap_instances_all_array[$i+4]}"  
                fi
            else
            if [ "$1" = "${sap_instances_all_array[$i]}" ]; then
                local sid_lower=${sap_instances_all_array[$i],,}
                su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_all_array[$i+3]} -function GetProcessList" >> /dev/null
                local result="$?"
                # Check the result and output accordingly
                # echo "Resultado: "$result""
                if [[ "$result" = "4"  ]]; then
                    echo "STOPPED - ${sap_instances_all_array[$i]} --> ${sap_instances_all_array[$i+1]}_${sap_instances_all_array[$i+2]}${sap_instances_all_array[$i+3]}_${sap_instances_all_array[$i+4]}" 
                    overall_exit_status=1
                elif [[ "$result" = "2" || "$result" = "0"  ]]; then
                    echo "PARTIALLY RUNNING - ${sap_instances_all_array[$i]} --> ${sap_instances_all_array[$i+1]}_${sap_instances_all_array[$i+2]}${sap_instances_all_array[$i+3]}_${sap_instances_all_array[$i+4]}" 
                    overall_exit_status=1
                elif  [[ "$result" = "3" ]]; then 
                    echo "RUNNING - ${sap_instances_all_array[$i]} --> ${sap_instances_all_array[$i+1]}_${sap_instances_all_array[$i+2]}${sap_instances_all_array[$i+3]}_${sap_instances_all_array[$i+4]}"  
                fi
            fi
            fi
        done
    fi
    return $overall_exit_status
}
function_instance_status_det(){
    local overall_exit_status=0
    local length=${#sap_instances_all_array[@]}
    # echo "Array length: $length"
    for (( i=0; i<(${length}); i+=5 ));
    do 
        if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then
            local sid_lower=${sap_instances_all_array[$i],,}
            # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_all_array[$i+3]} -function GetProcessList" >> /dev/null
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
            else
                if [ "$1" = "${sap_instances_all_array[$i]}" ]; then
                    echo -e "${sap_instances_all_array[$i]} --> ${sap_instances_all_array[$i+1]}_${sap_instances_all_array[$i+2]}${sap_instances_all_array[$i+3]}_${sap_instances_all_array[$i+4]}"
                    local sid_lower=${sap_instances_all_array[$i],,}
                    instance_found=1
                    su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_all_array[$i+3]} -function GetVersionInfo"          
                fi
            fi
            echo "=================================="
        done
        if [ "$instance_found" = "0" ]; then
            echo "Instance $1 not found"
        fi
    fi
}
function_find_saprouters() {
    # Clear previous information
    if [ ! -f "$SAPROUTER_STOPPED_WITH_SCRIPT" ]; then
        > "$SAPROUTER_INFO_FILE"
        # Find all saprouter processes
        ps -eo pid,user,args | grep '[s]aprouter' |grep -v "find_saprouter" | while read -r pid user args; do
            # Extract the full path of the saprouter executable
            full_path=$(pwdx $pid | awk '{print $2}')
            
            # Extract arguments excluding the executable
            arguments=$(echo "$args" | sed -e "s|^$full_path||")
            
            # Write information to file
            echo "$user|$full_path|$arguments" >> "$SAPROUTER_INFO_FILE"
        done
    else
        echo "Saprouter was stopped previously by this script. Not searching for saprouter processes."
        echo "Found saprouter info file at: $SAPROUTER_INFO_FILE"
        echo $SAPROUTER_INFO_FILE
    fi
}
function_stop_saprouters() {
    # Read the stored information and stop the saprouter processes
    while IFS='|' read -r user full_path arguments; do
        if [ -x "$full_path" ]; then
            # Stop the process as the original user using the stored arguments
            echo "Stopping saprouter: $full_path $arguments as user: $user"
            # su - "$user" -c "pkill -f '$full_path $arguments'"
            echo "Stopped saprouter: $full_path $arguments as user: $user"
        else
            echo "Executable $full_path not found or not executable."
        fi
    done < "$SAPROUTER_INFO_FILE"
}
function_start_saprouters() {
    # Read the stored information and start the saprouter processes
    while IFS='|' read -r user full_path arguments; do
        if [ -x "$full_path" ]; then
            # Start the process as the original user using the stored arguments
            echo "Starting saprouter: $full_path $arguments as user: $user"
            # su - "$user" -c "$full_path $arguments" &
            echo "Started saprouter: $full_path $arguments as user: $user"
        else
            echo "Executable $full_path not found or not executable."
        fi
    done < "$SAPROUTER_INFO_FILE"
}
# Checks status of SAP Systems as a whole without checking individual instances or databases
function_system_status(){
    if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then    
        for sid in "${sap_systems_array[@]}"; do
            echo "=== Checking status for SAP system: $sid"
            if ! function_instance_status "$sid"; then
                return 1
            fi
        done
    else
        echo "=== Checking status for SAP system: $sid"
        if ! function_instance_status "$1"; then
        return 1
        fi
    fi
}
# Stops SAP Systems as a whole without stopping individual instances or databases
function_system_stop(){
    if ! [ "$sap_systems_found" -eq 1 ]; then
        echo "No SAP Systems found."
    else
        local sap_abap_systems_length=${#sap_abap_systems_array[@]}
        local sap_java_systems_length=${#sap_java_systems_array[@]}
        local sap_instances_length=${#sap_instances_array[@]}
        local sap_java_instances_length=${#sap_java_instances_array[@]}
        local sap_hdb_systems_length=${#sap_hdb_systems_array[@]}
        local sap_contentserver_systems_length=${#sap_contentserver_systems_array[@]}
        if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then         
            # Stop JAVA systems first
            for (( i=0; i<(${sap_java_systems_length}); i+=1 )); do 
                local sid_lower=${sap_java_systems_array[$i],,}                                   
                local sys_num=""
                for (( j=0; j<(${sap_instances_length}); j+=5 )); do 
                    if [[ "${sap_java_systems_array[$i]}" == "${sap_instances_array[$j]}" ]]; then
                        # echo "Found instance $j for system ${sap_systems_array[$i]}"
                        sys_num=${sap_instances_array[$j+3]}
                        # echo "System number: $sys_num"
                        break            
                    fi
                done
                echo "Stopping JAVA system ==> ${sap_java_systems_array[$i]}"
                echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopSystem WaitforStopped 180"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_systems_array[$i+3]} -function StopSystem WaitforStopped 180"
                if [ $? -ne 0 ]; then
                    echo "! Error stopping SAP system: ${sap_systems_array[$i]}"
                    return 1
                fi
            done
            # Then stop non-JAVA systems
            for (( i=0; i<(${sap_abap_systems_length}); i+=1 )); do
                for a in "${sap_abap_systems_array[@]}"; do 
                    local sid_lower=${sap_abap_systems_array[$a],,}                                   
                    local sys_num=""
                    for (( j=0; j<(${sap_instances_length}); j+=5 )); do
                        if [[ "${sap_abap_systems_array[$a]}" == "${sap_instances_array[$j]}" ]]; then
                            # echo "Found instance $j for system ${sap_systems_array[$i]}"
                            sys_num=${sap_instances_array[$j+3]}
                            # echo "System number: $sys_num"
                            break
                        fi
                    done
                    echo "Stopping ABAP system ==> ${sap_systems_array[$a]}"
                    echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopSystem WaitforStopped 180"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_systems_array[$i+3]} -function StopSystem WaitforStopped 180"
                    if [ $? -ne 0 ]; then
                        echo "! Error stopping SAP system: ${sap_systems_array[$a]}"
                        return 1
                    fi
                done
            done
            # Then, stop Content Servers
            
            for (( i=0; i<(${sap_contentserver_systems_length}); i+=1 )); do 
                local sid_lower=${sap_contentserver_systems_array[$i],,}                                   
                local sys_num=""
                
                for (( j=0; j<(${sap_instances_length}); j+=5 )); do 
                    if [[ "${sap_contentserver_systems_array[$i]}" == "${sap_instances_array[$j]}" ]]; then
                        # echo "Found instance $j for system ${sap_systems_array[$i]}"
                        sys_num=${sap_instances_array[$j+3]}
                        # echo "System number: $sys_num"
                        break            
                    fi
                done
                echo "Stopping Content Server ==> ${sap_contentserver_systems_array[$i]}"
                echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopSystem WaitforStopped 180"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_systems_array[$i+3]} -function StopSystem WaitforStopped 180"
                if [ $? -ne 0 ]; then
                    echo "! Error stopping SAP system: ${sap_contentserver_systems_array[$i]}"
                    return 1
                fi
            done
            # Then, stop HDB systems if any
            for (( i=0; i<(${sap_hdb_systems_length}); i+=1 )); do 
                local sid_lower=${sap_hdb_systems_array[$i],,}                                   
                local sys_num=""
                for (( j=0; j<(${sap_instances_length}); j+=5 )); do 
                    if [[ "${sap_hdb_systems_array[$i]}" == "${sap_instances_array[$j]}" ]]; then
                        # echo "Found instance $j for system ${sap_systems_array[$i]}"
                        sys_num=${sap_instances_array[$j+3]}
                        # echo "System number: $sys_num"
                        break            
                    fi
                done
                echo "Stopping HDB system ==> ${sap_hdb_systems_array[$i]}"
                echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopSystem WaitforStopped 180"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_systems_array[$i+3]} -function StopSystem WaitforStopped 180"
                if [ $? -ne 0 ]; then
                    echo "! Error stopping SAP system: ${sap_systems_array[$i]}"
                    return 1
                fi
            done
        else
            local sid_lower=${1,,}
            local sys_num=""
            for (( j=0; j<(${sap_instances_length}); j+=5 )); do 
                if [[ "${sap_instances_array[$j]}" == "$1" ]]; then
                    # echo "Found instance $j for system ${sap_systems_array[$i]}"
                    sys_num=${sap_instances_array[$j+3]}
                    # echo "System number: $sys_num"
                    break            
                fi
            done
            if [[ -z "$sys_num" ]]; then
                echo "! Error: No instance found for SAP system $1"
                return 1
            fi
            echo "StopPing SAP system ==> $1"
            echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StopSystem WaitforStopped 180"
            # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_systems_array[$i+3]} -function StopSystem WaitforStopped 180"
            if [ $? -ne 0 ]; then
                echo "! Error stopping SAP system: $1"
                return 1
            fi
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
        local sap_instances_length=${#sap_instances_array[@]}
        local sap_java_instances_length=${#sap_java_instances_array[@]}
        local sap_hdb_systems_length=${#sap_hdb_systems_array[@]}
        if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then        
            # Start HDB systems
            for (( i=0; i<(${sap_hdb_systems_length}); i+=1 )); do 
                local sid_lower=${sap_hdb_systems_array[$i],,}                                   
                local sys_num=""
                for (( j=0; j<(${sap_instances_length}); j+=5 )); do 
                    if [[ "${sap_hdb_systems_array[$i]}" == "${sap_instances_array[$j]}" ]]; then
                        # echo "Found instance $j for system ${sap_systems_array[$i]}"
                        sys_num=${sap_instances_array[$j+3]}
                        # echo "System number: $sys_num"
                        break            
                    fi
                done
                echo "Starting HDB system ==> ${sap_hdb_systems_array[$i]}"
                echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartSystem WaitforStarted 180"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_systems_array[$i+3]} -function StartSystem WaitforStarted 180"
                if [ $? -ne 0 ]; then
                    echo "! Error starting SAP system: ${sap_systems_array[$i]}"
                    return 1
                fi
            done 
            # Start ABAP Systems 
            for (( i=0; i<(${sap_abap_systems_length}); i+=1 )); do
                for a in "${sap_abap_systems_array[@]}"; do 
                    local sid_lower=${sap_abap_systems_array[$a],,}                                   
                    local sys_num=""
                    for j in "${sap_instances_array[@]}"; do
                        if [[ "${sap_systems_array[$a]}" == "$j" ]]; then
                            # echo "Found instance $j for system ${sap_systems_array[$i]}"
                            sys_num=${sap_instances_array[$j+3]}
                            # echo "System number: $sys_num"
                            break
                        fi
                    done
                    echo "Starting ABAP system ==> ${sap_systems_array[$a]}"
                    echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartSystem WaitforStarted 180"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_systems_array[$i+3]} -function StartSystem WaitforStarted 180"
                    if [ $? -ne 0 ]; then
                        echo "! Error starting SAP system: ${sap_systems_array[$a]}"
                        return 1
                    fi
                done
            done
            # Start JAVA systems
            for (( i=0; i<(${sap_java_systems_length}); i+=1 )); do 
                local sid_lower=${sap_java_systems_array[$i],,}                                   
                local sys_num=""
                for (( j=0; j<(${sap_instances_length}); j+=5 )); do 
                    if [[ "${sap_java_systems_array[$i]}" == "${sap_instances_array[$j]}" ]]; then
                        # echo "Found instance $j for system ${sap_systems_array[$i]}"
                        sys_num=${sap_instances_array[$j+3]}
                        # echo "System number: $sys_num"
                        break            
                    fi
                done
                echo "Starting JAVA system ==> ${sap_java_systems_array[$i]}"
                echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartSystem WaitforStarted 180"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_systems_array[$i+3]} -function StartSystem WaitforStarted 180"
                if [ $? -ne 0 ]; then
                    echo "! Error starting SAP system: ${sap_systems_array[$i]}"
                    return 1
                fi
            done

        else
            local sid_lower=${1,,}
            local sys_num=""
            for (( j=0; j<(${sap_instances_length}); j+=5 )); do 
                if [[ "${sap_instances_array[$j]}" == "$1" ]]; then
                    # echo "Found instance $j for system ${sap_systems_array[$i]}"
                    sys_num=${sap_instances_array[$j+3]}
                    # echo "System number: $sys_num"
                    break            
                fi
            done
            if [[ -z "$sys_num" ]]; then
                echo "! Error: No instance found for SAP system $1"
                return 1
            fi
            echo "Starting SAP system ==> $1"
            echo "Command: su - ${sid_lower}adm -c sapcontrol -nr ${sys_num} -function StartSystem WaitforStopped 180"
            # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_systems_array[$i+3]} -function StartSystem WaitforStopped 180"
            if [ $? -ne 0 ]; then
                echo "! Error starting SAP system: $1"
                return 1
            fi
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
    saprouter_stop)
        function_stop_saprouters
        ;;
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