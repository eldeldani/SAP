#!/bin/bash
# SAP instance lookup tool for any host
# Created by Daniel Munoz
# For usage information, run:
# sap_instances.sh help 
# sap_instances.sh <command> [<option>]
# Where <command> can be:
#   instance_list [<SID>|all|<empty>]: 
#       lists all SAP instances found on the host
#   instance_status [detail|<SID>|<empty>] [<SID>]: 
#       shows the status of SAP instances found on the host
#   instance_version [<SID>|<empty>]:
#       shows the version of SAP instances found on the host
#   instance_stop: stops SAP instances found on the host
#   instance_start: starts SAP instances found on the host
#   instance_restart: restarts SAP instances found on the host
#   db_list: lists all non-HANA database instances found on the host. HANA databases are managed as an instance.
#   db_status: shows the status of database instances found on the host
#   db_stop: stops non-HANA database instances found on the host
#   db_start: starts non-HANA database instances found on the host
#   db_restart: restarts non-HANA database instances found on the host
#   db_type: shows the type of database instances found on the host
#   all_stop: stops all instances -including HANA instances- and non-HANA databases found on the host
#   all_start: starts all instances -including HANA instances- and non-HANA databases found on the host
# And <option> is an optional parameter depending on the command used.

# Example:
# sap_instances.sh instance_list
# sap_instances.sh instance_status detail
# sap_instances.sh instance_status <SID>
# sap_instances.sh instance_version <SID>
# sap_instances.sh instance_stop <SID|all>
# sap_instances.sh instance_start <SID|all>
# sap_instances.sh instance_restart <SID|all>
# sap_instances.sh db_list
# sap_instances.sh db_status <DBNAME|all>
# sap_instances.sh db_stop <DBNAME>
# sap_instances.sh db_start <DBNAME>
# sap_instances.sh db_restart <DBNAME>
# sap_instances.sh db_type <DBNAME>
# sap_instances.sh all_stop
# sap_instances.sh all_start


# DECLARE ARRAYS AND VARIABLES
declare -a sap_instances_array
declare -a non_hdb_instances_array
declare -a hdb_instances_array
declare sap_instances_found=0
declare saprouter_instance_found=0
declare non_hdb_instances_found=0
declare hdb_instances_found=0
declare saprouter_instance_found=0
declare SAPROUTER_INFO_FILE="/tmp/saprouter_info.txt"
declare SAPROUTER_STOPPED_WITH_SCRIPT="/tmp/saprouter_stopped_with_script.txt"

function_find_sap_instances(){
    if ! [ -f /usr/sap/sapservices ]; then
        return 1
    else
        while IFS= read -r line; do
        # Use a regular expression to extract the required part
        if [[ $line != \#* && $line =~ /usr/sap/([a-zA-Z0-9]{3})/SYS/profile/([a-zA-Z0-9]{3,5})_(D|DVEBMGS|ASCS|SCS|J|SMDA|HDB)([0-9]{2})_([a-zA-Z0-9]{1,13}) ]]; then
            SID=${BASH_REMATCH[1]}
            PROFSTRT=${BASH_REMATCH[2]}
            INSTANCE_TYPE=${BASH_REMATCH[3]}
            SN=${BASH_REMATCH[4]}
            VHOSTNAME=${BASH_REMATCH[5]}
            # Add entries to the array
            sap_instances_array+=("$SID")
            sap_instances_array+=("$PROFSTRT")
            sap_instances_array+=("$INSTANCE_TYPE")
            sap_instances_array+=("$SN")
            sap_instances_array+=("$VHOSTNAME")
            # Create the hostname string
            hostname="${SID} ${PROFSTRT}_${INSTANCE_TYPE}${SN}_${VHOSTNAME}"
            # hostname_array+=("$hostname")
        fi
        sap_instances_found=1
        done < "/usr/sap/sapservices"
    fi
}
function_find_non_hdb_instances(){
    if ! [ -x "/usr/sap/hostctrl/exe/saphostctrl" ]; then
        # echo "Error: /usr/sap/hostctrl/exe/saphostctrl not found or not executable. Can not detect database instances."
        return 1
    else
        # capture full command output (stdout+stderr) without printing it
        local raw_db_output
        raw_db_output=$(/usr/sap/hostctrl/exe/saphostctrl -function ListDatabaseSystems 2>&1)

        # keep the filtered lines used by the script, stored in db_list_output
        local db_list_output
        db_list_output=$(printf "%s" "$raw_db_output" | grep "Database name" | grep -v "hdb")
        if [[ -z "$db_list_output" ]]; then 
            # echo "No database instances found."
            return 1
        else
            while IFS= read -r line; do
                db_sid=$(echo "$line" | awk -F', ' '{print $1}' | awk '{print $3}')
                non_hdb_instances_array+=("$db_sid")
            done <<< "$db_list_output"
            non_hdb_instances_found=1
        fi
    fi
}
function_find_hdb_instances(){
    if ! [ -x "/usr/sap/hostctrl/exe/saphostctrl" ]; then
        # echo "Error: /usr/sap/hostctrl/exe/saphostctrl not found or not executable. Can not detect database instances."
        return 1
    else
        # capture full command output (stdout+stderr) without printing it
        local raw_db_output
        raw_db_output=$(/usr/sap/hostctrl/exe/saphostctrl -function ListDatabaseSystems 2>&1)

        # keep the filtered lines used by the script, stored in db_list_output
        local db_list_output
        db_list_output=$(printf "%s" "$raw_db_output" | grep "Database name" | grep "hdb")
        if [[ -z "$db_list_output" ]]; then 
            # echo "No HANA database instances found."
            return 1
        else
            while IFS= read -r line; do
                db_sid=$(echo "$line" | awk -F', ' '{print $1}' | awk '{print $3}')
                hdb_instances_array+=("$db_sid")
            done <<< "$db_list_output"
            hdb_instances_found=1
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
    if [ "$non_hdb_instances_found" -eq 0 ] && [ "$hdb_instances_found" -eq 0 ]; then
        echo "No database instances found."
        return 1
    elif [ "$hdb_instances_found" -eq 1 ]; then
        for db_sid in "${hdb_instances_array[@]}"; do
            echo "$db_sid"
        done
    elif [ "$non_hdb_instances_found" -eq 1 ]; then
        for non_hdb_sid in "${non_hdb_instances_array[@]}"; do
            echo "$non_hdb_sid"
        done
    fi
}   
function_db_type(){
    if [ "$non_hdb_instances_found" -eq 0 ] && [ "$hdb_instances_found" -eq 0 ]; then
        echo "No database instances found."
        return 1
    else
        local db_name="${1^^}"
        if [[ -z "$db_name" || ${#db_name} -ne 3 ]]; then
            echo "Error: Database name not supplied or not having exactly 3 characters"
            return 1
        else
            local dboutput=$(/usr/sap/hostctrl/exe/saphostctrl -function ListDatabaseSystems |grep -v SYSTEMDB|grep "Database name: ${db_name}")
            if [[ -z "$dboutput" ]]; then
                echo "Error: Unable to find database '$db_name' in saphostctrl output"
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
    if [ "$non_hdb_instances_found" -eq 0 ] && [ "$hdb_instances_found" -eq 0 ]; then
        echo "No database instances found."
    return 1
    else
        local db_name="${1^^}"
        if [[ -z "$db_name" || "$db_name" = "ALL" ]]; then
            /usr/sap/hostctrl/exe/saphostctrl -function ListDatabaseSystems|grep "Database name"
        elif [[ ${#db_name} -ne 3 ]]; then
                echo "Error: Database name not having exactly 3 characters"
                exit 1
        else
            local db_type
            if ! db_type=$(function_db_type $db_name); then
                echo "Error: Unable to determine database type for $db_name"
                return 1
            else
                /usr/sap/hostctrl/exe/saphostctrl -function GetDatabaseStatus -dbname $db_name -dbtype $db_type |head -1|awk '{ print $3 }'
                if [ ! $? -eq 0 ]; then
                    echo "=== Error executing command"
                fi
            fi
        fi
    fi
}
function_db_stop(){
    local db_name="${1^^}"
    local db_type
    if [ "$non_hdb_instances_found" -eq 0 ] && [ "$hdb_instances_found" -eq 0 ]; then
        echo "No database instances found to stop."
        return 1
    elif [ "$non_hdb_instances_found" -eq 1 ]; then
        if [[ "$db_name" = "ALL" ]]; then
            for sid in "${db_instances_array[@]}"; do
            local db_status
            if ! db_status=$(function_db_status $sid); then
                echo "No database associated with instance $sid. Skipping"
            else
                if ! function_db_stop $sid; then
                    echo "Error: Failed to stop database associated with instance $sid. Aborting."
                    return 1         
                fi
            fi 
            done
        else
            if ! db_type=$(function_db_type "$db_name"); then
                echo "Error: Unable to determine database type for $db_name"
                return 1
            else
                echo "Stopping database $db_name of type $db_type..."
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
                        echo "=== Failed to stop database $db_name even with force option."
                        return 1
                    fi
                fi
            fi
            echo "=== Checking database $db_name status..."
            /usr/sap/hostctrl/exe/saphostctrl -function GetDatabaseStatus -dbname "$db_name" -dbtype $db_type
        fi
    fi
}
function_db_start(){
    local db_name="${1^^}"
    local db_type
    if [ "$non_hdb_instances_found" -eq 0 ] && [ "$hdb_instances_found" -eq 0 ]; then
        echo "No database instances found to stop."
        return 1
    elif [ "$non_hdb_instances_found" -eq 1 ]; then
        if [[ "$db_name" = "ALL" ]]; then
            for sid in "${db_instances_array[@]}"; do
            local db_status
            if ! db_status=$(function_db_status $sid); then
                echo "No database associated with instance $sid. Skipping"
            else
                if ! function_db_start $sid; then
                    echo "Error: Failed to start database associated with instance $sid. Aborting."
                    return 1         
                fi
            fi 
            done
        else
            if ! db_type=$(function_db_type "$db_name"); then
                echo "Error: Unable to determine database type for $db_name"
                return 1
            else
                echo "=== Starting database $db_name of type $db_type..."
                echo "Command: /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $db_name -dbtype $db_type"
                # /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $db_name -dbtype $db_type
                if [ $? -eq 0 ]; then
                    echo "=== Database $db_name started successfully."
                else
                    echo "=== Failed to start database $db_name."
                    return 1
                fi
            fi
            echo "=== Checking database $db_name status..."
            /usr/sap/hostctrl/exe/saphostctrl -function GetDatabaseStatus -dbname $db_name -dbtype $db_type
        fi
    fi
}
function_db_restart(){
    local db_name="${1^^}"
    if ! function_db_stop $db_name; then
        return 1
    elif ! function_db_start $db_name; then
        return 1
    fi
}
# SAP INSTANCE FUNCTIONS
function_instance_list(){
    if ! [ "$sap_instances_found" -eq 1 ]; then
        echo "No SAP instances found."
    else
        local length=${#sap_instances_array[@]}
        for (( i=0; i<(${length}); i+=5 ));
        do 
            function_list_in(){
                echo "${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
            }
            if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then
                function_list_in
            else
                if [ "$1" = "${sap_instances_array[$i]}" ]; then
                    function_list_in
                fi
            fi
        done
    fi
}
function_instance_status(){
    if ! [ "$sap_instances_found" -eq 1 ]; then
        echo "No SAP instances found."
        return 1
    else
        if [ "$1" = "detail" ]; then
            local length=${#sap_instances_array[@]}
            # echo "Array length: $length"
            for (( i=0; i<(${length}); i+=5 ));
            do 
                if [[ -z "$2" || "$2" = "all" || "$1" = "None" ]]; then
                    local sid_lower=${sap_instances_array[$i],,}
                    su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function GetProcessList" >> /dev/null
                    echo -e "${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    case ${sap_instances_array[$i+2]} in
                    D)
                        echo "Instance Type: ${sap_instances_array[$i+2]} - Dialog Instance"
                        ;;
                    DVEBMGS)
                        echo "Instance Type: ${sap_instances_array[$i+2]} - Central Instance"
                        ;;
                    ASCS)
                        echo "Instance Type: ${sap_instances_array[$i+2]} - ABAP Central Services Instance"
                        ;;
                    SCS)
                        echo "Instance Type: ${sap_instances_array[$i+2]} - JAVA Central Services Instance"
                        ;;
                    J)
                        echo "Instance Type: ${sap_instances_array[$i+2]} - JAVA Instance"
                        ;;
                    SMDA)
                        echo "Instance Type: ${sap_instances_array[$i+2]} - Solution Manager Diagnostics Instance"
                        ;;
                    HDB)
                        echo "Instance Type: ${sap_instances_array[$i+2]} - HANA Platform Instance"
                        ;;
                    esac
                    # echo "Instance: ${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}"
                    # echo "Hostname: ${sap_instances_array[$i+4]}"
                    # echo "SAP Instance: ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function GetProcessList"
                    echo ""=====================================================""
                else
                    if [ "$2" = "${sap_instances_array[$i]}" ]; then
                        local sid_lower=${sap_instances_array[$i],,}
                        su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function GetProcessList" >> /dev/null
                        echo -e "${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                        case ${sap_instances_array[$i+2]} in
                        D)
                            echo "Instance Type: ${sap_instances_array[$i+2]} - Dialog Instance"
                            ;;
                        DVEBMGS)
                            echo "Instance Type: ${sap_instances_array[$i+2]} - Central Instance"
                            ;;
                        ASCS)
                            echo "Instance Type: ${sap_instances_array[$i+2]} - ABAP Central Services Instance"
                            ;;
                        SCS)
                            echo "Instance Type: ${sap_instances_array[$i+2]} - JAVA Central Services Instance"
                            ;;
                        J)
                            echo "Instance Type: ${sap_instances_array[$i+2]} - JAVA Instance"
                            ;;
                        SMDA)
                            echo "Instance Type: ${sap_instances_array[$i+2]} - Solution Manager Diagnostics Instance"
                            ;;
                        HDB)
                            echo "Instance Type: ${sap_instances_array[$i+2]} - HANA Platform Instance"
                            ;;
                        esac
                        # echo "Instance: ${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}"
                        # echo "Hostname: ${sap_instances_array[$i+4]}"
                        # echo "SAP Instance: ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                        su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function GetProcessList"
                        echo ""=====================================================""          
                    fi
                fi
            done
        elif [ "$1" = "binary" ]; then
            local overall_exit_status=0
            local length=${#sap_instances_array[@]}
            for (( i=0; i<(${length}); i+=5 ));
            do 
                local sid_lower=${sap_instances_array[$i],,}
                su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function GetProcessList" >> /dev/null
                # Check the result and output accordingly
                if ! [[ $? -eq 3 ]]; then
                    #echo "Result for SID: $sid Instance Number: $instance_number is not 3"
                    #echo "NOT RUNNING - ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}" 
                    overall_exit_status=1  # Set overall exit status to 1 if any result is not 3
                fi
            done
            exit $overall_exit_status  # Exit with the overall status
        
        else
            local length=${#sap_instances_array[@]}
            for (( i=0; i<(${length}); i+=5 ));
            do 
                if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then
                    local sid_lower=${sap_instances_array[$i],,}
                    su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function GetProcessList" >> /dev/null
                    result="$?"
                    # echo "Resultado ALL: "$result""
                    # Check the result and output accordingly
                    if [[ "$result" = "4"  ]]; then
                        echo "STOPPED - ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}" 
                    elif [[ "$result" = "2" || "$result" = "0"  ]]; then
                        echo "PARTIALLY RUNNING - ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}" 
                    elif  [[ "$result" = "3" ]]; then 
                        echo "RUNNING - ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"  
                    fi
                else
                if [ "$1" = "${sap_instances_array[$i]}" ]; then
                    local sid_lower=${sap_instances_array[$i],,}
                    su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function GetProcessList" >> /dev/null
                    local result="$?"
                    # Check the result and output accordingly
                    # echo "Resultado: "$result""
                    if [[ "$result" = "4"  ]]; then
                        echo "STOPPED - ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}" 
                    elif [[ "$result" = "2" || "$result" = "0"  ]]; then
                        echo "PARTIALLY RUNNING - ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}" 
                    elif  [[ "$result" = "3" ]]; then 
                        echo "RUNNING - ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"  
                    fi
                fi
                fi
            done
            exit $overall_exit_status  # Exit with the overall status
        fi
    fi
}
function_instance_version(){
    if ! [ "$sap_instances_found" -eq 1 ]; then
        echo "No SAP instances found."
        return 1
    else
        local length=${#sap_instances_array[@]}
        local instance_found=0
        for (( i=0; i<(${length}); i+=5 ));
        do 
            if [[ -z "$1" || "$1" = "all" || "$1" = "None" ]]; then
                instance_found=1
                echo -e "${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                local sid_lower=${sap_instances_array[$i],,}
                su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function GetVersionInfo"           
            else
                if [ "$1" = "${sap_instances_array[$i]}" ]; then
                    echo -e "${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    instance_found=1
                    su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function GetVersionInfo"          
                fi
            fi
            echo "=================================="
        done
        if [ "$instance_found" = "0" ]; then
            echo "Instance $1 not found"
        fi
    fi
}
function_instance_stop(){
    if ! [ "$sap_instances_found" -eq 1 ]; then
        echo "No SAP instances found."
        return 1
    else
        local length=${#sap_instances_array[@]}
        local instance_found=0
        # First pass: Stop the instances not being SCS, ASCS, or HDB
        for (( i=0; i<(${length}); i+=5 )); do 
            if [[ "${sap_instances_array[$i+2]}" != "SCS" && "${sap_instances_array[$i+2]}" != "ASCS" && "${sap_instances_array[$i+2]}" != "HDB" ]]; then
                if [ "$1" = "all" ]; then
                    echo -e "Stopping ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                    if [ $? -ne 0 ]; then
                        echo "=== Error stopping instance ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    fi
                    instance_found=1
                elif [ "$1" = "${sap_instances_array[$i]}" ]; then
                    echo -e "Stopping ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                    if [ $? -ne 0 ]; then
                        echo "=== Error stopping instance ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    fi
                    instance_found=1
                fi
            fi
        done
        
        # Second pass: Stop instances with SCS, ASCS
        for (( i=0; i<(${length}); i+=5 )); do 
            if [[ "${sap_instances_array[$i+2]}" == "SCS" || "${sap_instances_array[$i+2]}" == "ASCS" ]]; then
                if [ "$1" = "all" ]; then
                    echo -e "Stopping ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                    if [ $? -ne 0 ]; then
                        echo "=== Error stopping instance ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    fi
                    instance_found=1
                elif [ "$1" = "${sap_instances_array[$i]}" ]; then
                    echo -e "Stopping ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                    if [ $? -ne 0 ]; then
                        echo "=== Error stopping instance ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    fi
                    instance_found=1
                fi
            fi
        done

        # Third pass: Stop instances with HDB
        for (( i=0; i<(${length}); i+=5 )); do 
            if [[ "${sap_instances_array[$i+2]}" == "HDB" ]]; then
                if [ "$1" = "all" ]; then
                    echo -e "Stopping ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                    if [ $? -ne 0 ]; then
                        echo "=== Error stopping instance ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    fi
                    instance_found=1
                elif [ "$1" = "${sap_instances_array[$i]}" ]; then
                    echo -e "Stopping ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                    if [ $? -ne 0 ]; then
                        echo "=== Error stopping instance ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    fi
                    instance_found=1
                fi
            fi
        done

        if [ "$instance_found" = "0" ]; then
            echo "Instance $1 not found"
        fi
    fi
}
function_instance_start(){
    if ! [ "$sap_instances_found" -eq 1 ]; then
        echo "No SAP instances found."
        return 1
    else
        local length=${#sap_instances_array[@]}
        local instance_found=0

        # First pass: start instances with HDB
        for (( i=0; i<(${length}); i+=5 )); do
            if [[ "${sap_instances_array[$i+2]}" == "HDB" ]]; then
                if [ "$1" = "all" ]; then
                    instance_found=1
                    echo -e "Starting ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                    if [ $? -ne 0 ]; then
                        echo "=== Error starting instance ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    fi
                elif [ "$1" = "${sap_instances_array[$i]}" ]; then
                    instance_found=1
                    echo -e "Starting ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                    if [ $? -ne 0 ]; then
                        echo "=== Error starting instance ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    fi
                fi
            fi
        done
        # Second pass: start instances with SCS, ASCS
        for (( i=0; i<(${length}); i+=5 )); do
            if [[ "${sap_instances_array[$i+2]}" == "SCS" || "${sap_instances_array[$i+2]}" == "ASCS" ]]; then
                if [ "$1" = "all" ]; then
                    instance_found=1
                    echo -e "Starting ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                    if [ $? -ne 0 ]; then
                        echo "=== Error starting instance ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    fi
                elif [ "$1" = "${sap_instances_array[$i]}" ]; then
                    instance_found=1
                    echo -e "Starting ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                    if [ $? -ne 0 ]; then
                        echo "=== Error starting instance ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    fi
                fi
            fi
        done

        # Third pass: start the rest of the instances
        for (( i=0; i<(${length}); i+=5 )); do
            if [[ "${sap_instances_array[$i+2]}" != "SCS" && "${sap_instances_array[$i+2]}" != "ASCS" && "${sap_instances_array[$i+2]}" != "HDB" ]]; then
                if [ "$1" = "all" ]; then
                    instance_found=1
                    echo -e "Starting ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                    if [ $? -ne 0 ]; then
                        echo "=== Error starting instance ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    fi
                elif [ "$1" = "${sap_instances_array[$i]}" ]; then
                    instance_found=1
                    echo -e "Starting ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                    local sid_lower=${sap_instances_array[$i],,}
                    echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                    # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                    if [ $? -ne 0 ]; then
                        echo "=== Error starting instance ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
                    fi
                fi
            fi
        done

        if [ "$instance_found" = "0" ]; then
            echo "Instance $1 not found"
        fi
    fi
}
function_instance_restart(){
    if ! [ "$sap_instances_found" -eq 1 ]; then
        echo "No SAP instances found."
    else
        if ! function_instance_stop $1; then
            echo "Error: Failed to stop instance $1. Aborting restart."
            exit 1
        elif ! function_instance_start $1; then
            echo "Error: Failed to start instance $1 after stopping."
            exit 1
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
function_all_stop(){
    function_instance_stop all
    function_db_stop all
}
function_all_start(){
    function_db_start all
    function_instance_start all
}


## Main script logic
# Check if the number of arguments is correct
if [ "$#" -lt 1 ] || [ "$1" = "help" ]; then
    function_display_help
    exit 0
fi
# Find SAP and DB instances
function_find_sap_instances
function_find_hdb_instances
function_find_non_hdb_instances
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
        function_instance_status $arg2 $arg3
        ;;
    instance_version)
        function_instance_version $arg2
        ;;
    instance_stop)
        if [[ -z "$arg2" ]]; then
            echo "Error: 'option' is required for 'instance_stop' command."
            function_display_help
            exit 1
        elif [ "$sap_instances_found" -ne 1 ]; then
            echo "No SAP instances found."
            exit 1
        else
            function_instance_stop $arg2
        fi
        ;;
    instance_start)
        if [[ -z "$arg2" ]]; then
            echo "Error: 'option' is required for 'instance_start' command."
            function_display_help
            exit 1
        elif [ "$sap_instances_found" -ne 1 ]; then
            echo "No SAP instances found."
            exit 1
        else
            function_instance_start $arg2
        fi
        ;;
    instance_restart)
        if [[ -z "$arg2" ]]; then
            echo "Error: 'option' is required for 'instance_restart' command."
            function_display_help
            exit 1
        elif [ "$sap_instances_found" -ne 1 ]; then
            echo "No SAP instances found."
            exit 1
        else
            function_instance_restart $arg2
        fi
        ;;
    db_list)
        function_db_list
        ;;
    db_status)
        function_db_status $arg2
        ;;
    db_stop)
        if [[ -z "$arg2" ]]; then
            echo "Error: 'option' is required for 'db_stop' command."
            function_display_help
            exit 1
        fi
        function_db_stop $arg2
        ;;
    db_start)
        if [[ -z "$arg2" ]]; then
            echo "Error: 'option' is required for 'db_start' command."
            function_display_help
            exit 1
        fi
        function_db_start $arg2
        ;;
    db_restart)
        if [[ -z "$arg2" ]]; then
            echo "Error: 'option' is required for 'db_restart' command."
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
    # find_saprouter)
    #     function_find_saprouters
    #     ;;
    *)
        echo "Error: 'command' must be 'instance_list', 'instance_status', 'instance_version', 'instance_stop', 'instance_start', 'instance_restart', 'db_status', 'db_stop', 'db_start', 'db_restart', 'db_type', 'all_stop' or 'all_start'"
        function_display_help
        exit 1
        ;;
esac