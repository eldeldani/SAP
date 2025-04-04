#!/bin/bash
# SAP instance lookup tool for any host
# Created by Daniel Munoz
# Usage:
# <TBD>

# Initialize an empty array
declare -a hostname_array
declare -a sap_instances_array
# Read each line from the file
while IFS= read -r line; do
    # Use a regular expression to extract the required part
    if [[ $line =~ ([a-zA-Z0-9]{3})_(D|DVEBMGS|ASCS|SCS|J|SMDA)([0-9]{2})_([a-zA-Z0-9]{1,13}) ]]; then
        SID=${BASH_REMATCH[1]}
        INSTANCE_TYPE=${BASH_REMATCH[2]}
        SN=${BASH_REMATCH[3]}
        VHOSTNAME=${BASH_REMATCH[4]}
        # Add entries to the array
        sap_instances_array+=("$SID")
        sap_instances_array+=("$INSTANCE_TYPE")
        sap_instances_array+=("$SN")
        sap_instances_array+=("$VHOSTNAME")
        # Create the hostname string
        hostname="${SID}_${INSTANCE_TYPE}${NN}_${VHOSTNAME}"
        hostname_array+=("$hostname")
    fi
done < "/usr/sap/sapservices"  # Replace "your_file.txt" with the actual filename

# Print the array elements
# for host in "${hostname_array[@]}"; do
#     echo "$host"
# done
length=${#sap_instances_array[@]}
# echo "Array length: $length"
for (( i=0; i<(${length}); i+=4 ));
do 
    # echo "System ID: ${sap_instances_array[$i]}"
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
    # echo "Instance Number: ${sap_instances_array[$i+2]}"
    # echo "Hostname: ${sap_instances_array[$i+3]}"
    echo "SAP Instance: ${sap_instances_array[$i]}_${sap_instances_array[$i+1]}${sap_instances_array[$i+2]}_${sap_instances_array[$i+3]}"
    sid_lower=${sap_instances_array[$i],,}
    su - ${sid_lower}"adm" -c "sapcontrol -nr ${sap_instances_array[$i+2]} -host ${sap_instances_array[$i+3]} -function GetProcessList"
    echo "=================================="
done