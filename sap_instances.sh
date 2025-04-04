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
    if [[ $line =~ /usr/sap/([a-zA-Z0-9]{3})/SYS/profile/([a-zA-Z0-9]{3,5})_(D|DVEBMGS|ASCS|SCS|J|SMDA|HDB)([0-9]{2})_([a-zA-Z0-9]{1,13}) ]]; then
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
    # Print the array elements
    # for host in "${hostname_array[@]}"; do
    #     echo "$host"
    # done
    length=${#sap_instances_array[@]}
    # echo "Array length: $length"
    for (( i=0; i<(${length}); i+=5 ));
    do 
        echo "${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
        # case ${sap_instances_array[$i+1]} in
        # D)
        #     echo "Instance Type: ${sap_instances_array[$i+1]} - Dialog Instance"
        #     ;;
        # DVEBMGS)
        #     echo "Instance Type: ${sap_instances_array[$i+1]} - Central Instance"
        #     ;;
        # ASCS)
        #     echo "Instance Type: ${sap_instances_array[$i+1]} - ABAP Central Services Instance"
        #     ;;
        # SCS)
        #     echo "Instance Type: ${sap_instances_array[$i+1]} - JAVA Central Services Instance"
        #     ;;
        # J)
        #     echo "Instance Type: ${sap_instances_array[$i+1]} - JAVA Instance"
        #     ;;
        # SMDA)
        #     echo "Instance Type: ${sap_instances_array[$i+1]} - Solution Manager Diagnostics Instance"
        #     ;;
        # esac
        # echo "Instance: ${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}"
        # echo "Hostname: ${sap_instances_array[$i+3]}"
        # echo "SAP Instance: ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
        # sid_lower=${sap_instances_array[$i],,}
        # su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+2]} -host ${sap_instances_array[$i+3]} -function GetProcessList"
        # echo "=================================="
    done

}

function_status(){
    if [ "$1" = "detail" ]; then
            length=${#sap_instances_array[@]}
        # echo "Array length: $length"
        for (( i=0; i<(${length}); i+=5 ));
        do 
            
            echo -e "\033[1;33m${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}\033[0m"
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
            sid_lower=${sap_instances_array[$i],,}
            su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+3]} -host ${sap_instances_array[$i+4]} -function GetProcessList"
            echo "=================================="
        done
    elif [ "$1" = "binary" ]; then
        echo "not implemented"
    fi

}

# Check if the number of arguments is correct
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 command options"
    echo "command can be: list, profiles, or status"
    echo "option specifications depend on command"
    exit 1
fi

# Assign arguments to variables
arg1=$1
arg2=$2

# Validate arg1 and command
case $arg1 in
    list)
        # 'list' requires no specific command, so it's valid
        # echo "command: 'list' is valid. 'option' 2 is not needed."
        function_list
        ;;
    profiles)
        if [[ "$arg2" == "parameter" ]]; then
            echo "'command': 'profiles' is valid with 'option': 'parameter'."
        else
            echo "Error: command must be 'parameter' when arg1 is 'profiles'."
            exit 1
        fi
        ;;
    status)
        if [[ "$arg2" == "binary" || "$arg2" == "detail" ]]; then
            # echo "'command': 'status' is valid with 'option': '$arg2'."
            function_status $arg2
        else
            echo "Error: 'command' must be 'binary' or 'detail' when arg1 is 'status'."
            exit 1
        fi
        ;;
    *)
        echo "Error: 'command' must be 'list', 'profiles', or 'status'."
        exit 1
        ;;
esac


