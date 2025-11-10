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



# Functions 
function_list(){
    length=${#sap_instances_array[@]}
    for (( i=0; i<(${length}); i+=5 ));
    do 
        function_list_in(){
            echo "${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
        }
        if [[ "$1" = "all" || "$1" = "None" ]]; then
            function_list_in
        else
            if [ "$1" = "${sap_instances_array[$i]}" ]; then
                function_list_in
            fi
        fi
        
    done
}

function_status(){
    if [ "$1" = "detail" ]; then
        length=${#sap_instances_array[@]}
        # echo "Array length: $length"
        for (( i=0; i<(${length}); i+=5 ));
        do 
            if [[ "$2" = "all" || "$1" = "None" ]]; then
                sid_lower=${sap_instances_array[$i],,}
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
                sid_lower=${sap_instances_array[$i],,}
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
        overall_exit_status=0
        length=${#sap_instances_array[@]}
        for (( i=0; i<(${length}); i+=5 ));
        do 
            sid_lower=${sap_instances_array[$i],,}
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
        length=${#sap_instances_array[@]}
        for (( i=0; i<(${length}); i+=5 ));
        do 
            if [[ "$1" = "all" || "$1" = "None" ]]; then
                sid_lower=${sap_instances_array[$i],,}
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
                sid_lower=${sap_instances_array[$i],,}
                su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function GetProcessList" >> /dev/null
                result="$?"
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

function_version(){
    length=${#sap_instances_array[@]}
    instance_found=0
    for (( i=0; i<(${length}); i+=5 ));
    do 
        if [[ "$1" = "all" || "$1" = "None" ]]; then
            instance_found=1
            echo -e "${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
            sid_lower=${sap_instances_array[$i],,}
            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function GetVersionInfo"           
        else
            if [ "$1" = "${sap_instances_array[$i]}" ]; then
                echo -e "${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                sid_lower=${sap_instances_array[$i],,}
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

function_stop(){
    length=${#sap_instances_array[@]}
    instance_found=0
    for (( i=0; i<(${length}); i+=5 ));
    do 
        if [ "$1" = "all" ]; then
            echo -e "${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
            sid_lower=${sap_instances_array[$i],,}
            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"
        else
            if [ "$1" = "${sap_instances_array[$i]}" ]; then
                echo -e "Stopping ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                sid_lower=${sap_instances_array[$i],,}
                instance_found=1
                su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Stop"          
            fi
        fi
    done
    if [ "$instance_found" = "0" ]; then
        echo "Instance $1 not found"
    fi
}

function_start(){
    length=${#sap_instances_array[@]}
    instance_found=0
    for (( i=0; i<(${length}); i+=5 ));
    do 
        if [ "$1" = "all" ]; then
            instance_found=1
            echo -e "${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
            sid_lower=${sap_instances_array[$i],,}
            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"
        else
            if [ "$1" = "${sap_instances_array[$i]}" ]; then
                echo -e "Starting ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                sid_lower=${sap_instances_array[$i],,}
                instance_found=1
                su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function Start"          
            fi
        fi
    done
    if [ "$instance_found" = "0" ]; then
        echo "Instance $1 not found"
    fi
}

function_restart(){
    length=${#sap_instances_array[@]}
    instance_found=0
    for (( i=0; i<(${length}); i+=5 ));
    do 
        if [ "$1" = "all" ]; then
            instance_found=1
            echo -e "${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
            sid_lower=${sap_instances_array[$i],,}
            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function RestartInstance"
        else
            if [ "$1" = "${sap_instances_array[$i]}" ]; then
                echo -e "Starting ==> ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
                sid_lower=${sap_instances_array[$i],,}
                instance_found=1
                su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -function RestartInstance"          
            fi
        fi
    done
    if [ "$instance_found" = "0" ]; then
        echo "Instance $1 not found"
    fi
}

function_statusdb(){
    if [ "$1" = "all" ]; then
        /usr/sap/hostctrl/exe/saphostctrl -function ListDatabases
    elif [ -z "$2" ]; then
        echo "Error: Database type argument is missing: syb or hdb"
        echo "Usage: $0 statusdb <SID> <dbtype>"
        exit 1
    else
        /usr/sap/hostctrl/exe/saphostctrl -function GetDatabaseStatus -dbname $1 -dbtype $2
        if [ ! $? -eq 0 ]; then
            echo "=== Error executing command"
        fi
    fi
}

function_stopdb(){
    if [ -z "$2" ]; then
        echo "Error: Database type argument is missing: syb or hdb"
        echo "Usage: $0 stopdb <SID> <dbtype>"
        exit 1
    fi
    echo "Stopping database $1 of type $2..."
    /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $1 -dbtype $2
    if [ $? -eq 0 ]; then
        echo "=== Database $1 stopped successfully."
    else
        echo "=== Failed to stop database $1. Trying with force option..."
        /usr/sap/hostctrl/exe/saphostctrl -function StopDatabase -dbname $1 -dbtype $2 -force
        if [ $? -eq 0 ]; then
            echo "=== Database $1 stopped successfully with force option."
        else
            echo "=== Failed to stop database $1 even with force option."
        fi
    fi
    echo "=== Checking database $1 status..."
    /usr/sap/hostctrl/exe/saphostctrl -function GetDatabaseStatus -dbname $1 -dbtype $2
}

function_startdb(){
    if [ -z "$2" ]; then
        echo "Error: Database type argument is missing: syb or hdb"
        echo "Usage: $0 startdb <SID> <dbtype>"
        exit 1
    fi
    echo "=== Starting database $1 of type $2..."
    /usr/sap/hostctrl/exe/saphostctrl -function StartDatabase -dbname $1 -dbtype $2
    if [ $? -eq 0 ]; then
        echo "=== Database $1 started successfully."
    else
        echo "=== Failed to start database $1."
    fi
    echo "=== Checking database $1 status..."
    /usr/sap/hostctrl/exe/saphostctrl -function GetDatabaseStatus -dbname $1 -dbtype $2
}

function_restartdb(){
    if [ -z "$2" ]; then
        echo "Error: Database type argument is missing: syb or hdb"
        echo "Usage: $0 restartdb <SID> <dbtype>"
        exit 1
    fi
    echo "=== Restarting database $1 of type $2..."
    echo "=== Stopping database $1..."
    function_stopdb $1 $2
    echo "=== Starting database $1..."
    function_startdb $1 $2
}

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
    list)
        # 'list' requires no specific command, so it's valid
        function_list $arg2
        ;;
    profiles)
        # 'profiles' requires an additional argument: parameter
        if [[ "$arg2" == "parameter" ]]; then
            echo "'command': 'profiles' is valid with 'option': 'parameter'."
        else
            echo "Error: command must be 'parameter' when arg1 is 'profiles'."
            exit 1
        fi
        ;;
    status)
        function_status $arg2 $arg3
        ;;
    version)
        function_version $arg2
        ;;
    stop)
        function_stop $arg2
        ;;
    start)
        function_start $arg2
        ;;
    restart)
        function_restart $arg2
        ;;
    statusdb)
        function_statusdb $arg2 $arg3
        ;;
    stopdb)
        function_stopdb $arg2 $arg3
        ;;
    startdb)
        function_startdb $arg2 $arg3
        ;;
    restartdb)
        function_restartdb $arg2 $arg3
        ;;
    *)
        echo "Error: 'command' must be 'list', 'status', 'version', 'profiles', 'stop', 'start', 'statusdb', 'stopdb' , 'startdb' or 'restart'"
        exit 1
        ;;
esac           