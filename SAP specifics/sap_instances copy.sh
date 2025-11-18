#!/bin/bash
# SAP instance lookup tool for any host
# Created by Daniel Munoz
# Usage:
# sap_instances.sh <command> <option>
# <command>:
#   list: Lists Available SAP instances in host. Configured in /usr/sap/sapservices
#   profiles: Lists available profiles
#        <option>:
#           parameter: returns value for given parameter for every instance, including default
#   status: Checks SAP instances status in the host
#       <option>
#           binary: returns 0 if all instances are running or 1 otherwise.
#           detail: returns sapcontrol output command for every instance

# Load SAP instances data from /usr/sap/sapservices
declare -a hostname_array
declare -a sap_instances_array
# Read each line from the file
while IFS= read -r line; do
    # Use a regular expression to extract the required part
    # if [[ $line =~ (\/usr\/sap\/)([a-zA-Z0-9]{3})*([a-zA-Z0-9]{3,5})_(D|DVEBMGS|ASCS|SCS|J|SMDA)([0-9]{2})_([a-zA-Z0-9]{1,13}) ]]; then
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
        hostname_array+=("$hostname")
    fi
done < "/usr/sap/sapservices"  # Replace "your_file.txt" with the actual filename


# SID: ${sap_instances_array[$i]}
# INSTANCE_TYPE: ${sap_instances_array[$i+2]}
# SN: ${sap_instances_array[$i+3]}
# HOSTNAME: ${sap_instances_array[$i+4]}


# DATABASE FUNCTIONS
# Database type identification 
function_db_type(){
    local db_name="${1^^}"
    # Ensure the hostctrl binary exists and is executable
    if [ ! -x "/usr/sap/hostctrl/exe/saphostctrl" ]; then
        echo "Error: /usr/sap/hostctrl/exe/saphostctrl not found or not executable"
        return 1
    fi
    if [[ -z "$db_name" || ${#db_name} -ne 3 ]]; then
        echo "Error: Database name not supplied or not having exactly 3 characters"
        return 1
    else
        # Proper command substitution (no quotes around the entire command)
        local dboutput=$(/usr/sap/hostctrl/exe/saphostctrl -function ListDatabaseSystems |grep -v SYSTEMDB|grep "Database name: ${db_name}")
        if [[ -z "$dboutput" ]]; then
            echo "Error: Unable to find database '$db_name' in saphostctrl output"
            return 1
        else
            # dbinstance=$(echo "$dboutput" | grep -i instance | awk -F', *' '{print $1}' | awk -F': *' '{print $2}')
            echo $dboutput |head -1| awk -F'Type: ' '{ split($2, a, ","); print a[1] }'
            # dbname=$(echo "$dboutput" | grep -i "database name" | awk -F', *' '{print $1}' | awk -F': *' '{print $2}')
        fi
    fi
}

# Get database status
function_db_status(){
    local db_name="${1^^}"
    if [[ -z "$db_name" || "$db_name" = "all" ]]; then
        /usr/sap/hostctrl/exe/saphostctrl -function ListDatabaseSystems|grep "Database name"
    else
        if [[ ${#db_name} -ne 3 ]]; then
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
# Stop database
function_db_stop(){
    local db_name="${1^^}"
    local db_type
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
}
# Start database
function_db_start(){
    local db_name="${1^^}"
    local db_type
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
}
# Restart database
function_db_restart(){
    local db_name="${1^^}"
    if ! function_db_stop $db_name; then
        echo "Error: Failed to stop database $db_name. Aborting restart."
        exit 1
    elif ! function_db_start $db_name; then
        echo "Error: Failed to start database $db_name after stopping."
        exit 1
    fi
}
function_instance_list(){
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
}
function_instance_status(){
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

}
function_instance_version(){
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
}
function_instance_stop(){
    local length=${#sap_instances_array[@]}
    local instance_found=0

    # First pass: Stop the instances not being SCS or ASCS
    for (( i=0; i<(${length}); i+=5 )); do 
        if [[ "${sap_instances_array[$i+2]}" != "SCS" && "${sap_instances_array[$i+2]}" != "ASCS" ]]; then
            if [ "$1" = "all" ]; then
                echo -e "Stopping ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                local sid_lower=${sap_instances_array[$i],,}
                echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                instance_found=1
            elif [ "$1" = "${sap_instances_array[$i]}" ]; then
                echo -e "Stopping ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                local sid_lower=${sap_instances_array[$i],,}
                echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                instance_found=1
            fi
        fi
    done
    
    # Second pass: Stop instances with SCS or ASCS
    for (( i=0; i<(${length}); i+=5 )); do 
        if [[ "${sap_instances_array[$i+2]}" == "SCS" || "${sap_instances_array[$i+2]}" == "ASCS" ]]; then
            if [ "$1" = "all" ]; then
                echo -e "Stopping ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                local sid_lower=${sap_instances_array[$i],,}
                echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                instance_found=1
            elif [ "$1" = "${sap_instances_array[$i]}" ]; then
                echo -e "Stopping ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                local sid_lower=${sap_instances_array[$i],,}
                echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
                instance_found=1
            fi
        fi
    done

    

    if [ "$instance_found" = "0" ]; then
        echo "Instance $1 not found"
    fi
}
function_instance_start(){
    local length=${#sap_instances_array[@]}
    local instance_found=0

    # First pass: start instances with SCS or ASCS
    for (( i=0; i<(${length}); i+=5 )); do
        if [[ "${sap_instances_array[$i+2]}" == "SCS" || "${sap_instances_array[$i+2]}" == "ASCS" ]]; then
            if [ "$1" = "all" ]; then
                instance_found=1
                echo -e "Starting ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                local sid_lower=${sap_instances_array[$i],,}
                echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
            elif [ "$1" = "${sap_instances_array[$i]}" ]; then
                instance_found=1
                echo -e "Starting ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                local sid_lower=${sap_instances_array[$i],,}
                echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
            fi
        fi
    done

    # Second pass: start the rest of the instances
    for (( i=0; i<(${length}); i+=5 )); do
        if [[ "${sap_instances_array[$i+2]}" != "SCS" && "${sap_instances_array[$i+2]}" != "ASCS" ]]; then
            if [ "$1" = "all" ]; then
                instance_found=1
                echo -e "Starting ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                local sid_lower=${sap_instances_array[$i],,}
                echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
            elif [ "$1" = "${sap_instances_array[$i]}" ]; then
                instance_found=1
                echo -e "Starting ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                local sid_lower=${sap_instances_array[$i],,}
                echo "command: su - ${sid_lower}adm -c sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
                # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
            fi
        fi
    done

    if [ "$instance_found" = "0" ]; then
        echo "Instance $1 not found"
    fi
}
function_instance_restart(){
    if ! function_instance_stop $1; then
        echo "Error: Failed to stop instance $1. Aborting restart."
        exit 1
    elif ! function_instance_start $1; then
        echo "Error: Failed to start instance $1 after stopping."
        exit 1
    fi
}
function_all_stop(){
    local length=${#sap_instances_array[@]}
    if ! function_instance_stop "all"; then
        echo "Error: Failed to stop SAP instances. Aborting."
        exit 1
    fi

    # For every instance check if we have a valid running database in the host and stop it
    local -A seen_sids
    local -A unique_sids
    # echo "seen_sids initialized with values: ${!seen_sids[@]}"
    for (( i=0; i<(${length}); i+=5 )); do
        local sid="${sap_instances_array[$i]}"
        if [[ ! -n "${seen_sids[$sid]}" ]]; then
            unique_sids+=([$sid]=1)
            seen_sids[$sid]=1
        fi
    # echo "seen_sids updated with values: ${!seen_sids[@]}"
    done
    for sid in "${!unique_sids[@]}"; do
        # echo "Processing SID: $sid"
        local db_status
        if ! db_status=$(function_db_status $sid); then
            echo "No database associated with instance $sid or database not running. Skipping"
        else
            if [[ "$db_status" = *"Stopped"* ]]; then
                echo "Database $sid is not running. Skipping stop."
                continue
            elif ! function_db_stop $sid; then
                echo "Error: Failed to stop database associated with instance $sid. Aborting."
                exit 1         
            fi
        fi
    done
}

function_all_start(){
    local length=${#sap_instances_array[@]}
    # For every instance check if we have a valid database in the host and start it
    local -A seen_sids=()
    for (( i=0; i<(${length}); i+=5 )); do
        local sid="${sap_instances_array[$i]}"
        # skip if already processed
        if [[ -n "${seen_sids[$sid]}" ]]; then
            local db_status
            if ! db_status=$(function_db_status $sid); then
                echo "No database associated with instance $sid or database not running. Skipping"
            else
                if [[ "$db_status" = *"Running"* ]]; then
                    echo "Database $sid is already running. Skipping start."
                    continue
                elif ! function_db_start $sid; then
                    echo "Error: Failed to start database associated with instance $sid. Aborting."
                    exit 1         
                fi
            fi 
        fi
        seen_sids[$sid]=1
    done

    if ! function_instance_start "all"; then
        echo "Error: Failed to start SAP instances. Aborting."
        exit 1
    fi
}
## Main script logic
# Check if the number of arguments is correct
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 command options"
    echo "Error: 'command' must be 'list', 'status', 'version', 'profiles', 'stop', 'start' or 'restart'"
    echo "option specifications depend on command"
    exit 1
fi

# Assign arguments to variables
arg1=$1
arg2=$2
arg3=$3
arg4=$4

# Validate arg1 and command
case $arg1 in
    instance_list)
        # 'list' requires no specific command, so it's valid
        function_instance_list $arg2
        ;;
    instance_profiles)
        # 'profiles' requires an additional argument: parameter
        if [[ "$arg2" == "parameter" ]]; then
            echo "'command': 'profiles' is valid with 'option': 'parameter'."
            echo "Functionality not yet implemented."
            # Here you would call the function to handle profiles and parameters
        else
            echo "Error: command must be 'parameter' when arg1 is 'profiles'."
            exit 1
        fi
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
            exit 1
        fi
        function_instance_stop $arg2
        ;;
    instance_start)
        if [[ -z "$arg2" ]]; then
            echo "Error: 'option' is required for 'instance_start' command."
            exit 1
        fi
        function_instance_start $arg2
        ;;
    instance_restart)
        if [[ -z "$arg2" ]]; then
            echo "Error: 'option' is required for 'instance_restart' command."
            exit 1
        fi
        function_instance_restart $arg2
        ;;
    db_status)
        function_db_status $arg2
        ;;
    db_stop)
        if [[ -z "$arg2" ]]; then
            echo "Error: 'option' is required for 'db_stop' command."
            exit 1
        fi
        function_db_stop $arg2
        ;;
    db_start)
        if [[ -z "$arg2" ]]; then
            echo "Error: 'option' is required for 'db_start' command."
            exit 1
        fi
        function_db_start $arg2
        ;;
    db_restart)
        if [[ -z "$arg2" ]]; then
            echo "Error: 'option' is required for 'db_restart' command."
            exit 1
        fi
        function_db_restart $arg2
        ;;
    db_type)
        function_db_type $arg2
        ;;
    all_stop)
        function_all_stop $arg2
        ;;
    all_start)
        function_all_start $arg
        ;;
    *)
        echo "Error: 'command' must be 'instance_list', 'instance_status', 'instance_version', 'instance_profiles', 'instance_stop', 'instance_start', 'db_status', 'db_stop' , 'db_start' or 'db_restart'"
        exit 1
        ;;
esac