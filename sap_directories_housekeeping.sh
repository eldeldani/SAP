#!/bin/bash

##### Script output

# Redirect output and errors to output.log
current_date=$(date +%Y-%m-%d)
exec >> /tmp/sap_directories_housekeeping_$current_date.log 2>&1

##### Editable variables

# retention_months set the desired months to be retained
retention_months=24


# Array declaration for the file patterns to cleanup, You can edit by extending the patterns:
file_pattern_array=( OO* *.ARCHIVE FBI* gw_log* *.trc *.old.* *.old dev_* )

# Variables transformation
retention_days=$((retention_months * 31))


## Initialize an array with unique SAP SIDs
my_array=()

# Read from the file line by line
while IFS= read -r line; do
    # Use regex to extract the desired substring
    if [[ $line =~ /usr/sap/([^/]{3}) ]]; then
        my_array+=("${BASH_REMATCH[1]}") # Append to the array
    fi
done < "/usr/sap/sapservices" # Replace with your actual filename

# Initialize an associative array to track seen values
declare -A seen
sid_array=()

# Iterate through the original array
for item in "${my_array[@]}"; do
    if [[ -z "${seen[$item]}" ]]; then
        seen[$item]=1      # Mark item as seen
        sid_array+=("$item")  # Append to unique array
    fi
done

#### Output summary before execution
echo "======================================================================="
echo "$(date): Script started in $HOSTNAME"
if [ "$1" != "execute" ]; then
        echo -e "$(date): Script being executed in test mode, only listing, not deleting"
else
        echo -e "$(date): Script being executed in EXECUTION mode, it will delete."
fi
echo "$(date): SAP SIDs to analyze: ${sid_array[@]}"
echo "$(date): The following file patterns will be used: ${file_pattern_array[@]}"
echo "$(date): Files older than $retention_days days will be deleted"

for sap_sid in ${sid_array[@]}
do
        # You can edit this paths by adding new ones
        global=/usr/sap/$sap_sid/SYS/global
        work_ascs=/usr/sap/$sap_sid/ASCS[0-9][0-9]/work
        work_scs=/usr/sap/$sap_sid/SCS[0-9][0-9]/work
        work_ci=/usr/sap/$sap_sid/DVEBMGS[0-9][0-9]/work
        work_dia=/usr/sap/$sap_sid/D[0-9][0-9]/work
        work_java=/usr/sap/$sap_sid/J[0-9][0-9]/work

        paths_array=( $global $work_ascs $work_scs $work_ci $work_dia $work_java )

        # Loop for every directory
        for dir in ${paths_array[@]}
        do
                        if [ -d "$dir" ];then
                                        #echo -e "$(date): Working on directory: $dir"
                                        for pattern in ${file_pattern_array[@]}
                                        do
                                                files=$(find -L $dir -maxdepth 1 -name "$pattern" -mtime +$retention_days -type f)
                                                if [ -n "$files" ]; then
                                                        if [ "$1" != "execute" ]; then
                                                                echo -e "$(date): The following files would be deleted on directory: $dir for pattern: $pattern if not in test mode, only listing..."
                                                                find -L $dir -maxdepth 1 -name "$pattern" -mtime +$retention_days -type f -printf '%TY-%Tm-%Td %p\n' | sort -rn
                                                        else
                                                                echo -e "$(date): The following files will be deleted on directory: $dir for pattern: $pattern"
                                                                find -L $dir -maxdepth 1 -name "$pattern" -mtime +$retention_days -type f -printf '%TY-%Tm-%Td %p\n' | sort -rn
                                                                echo -e "$(date): Deleting the files..."
                                                                #find -L $dir -maxdepth 1 -name "$pattern" -mtime +$retention_days -type f -deleteX
                                                        fi
                                                fi
                                        done
                        fi
        done
done
