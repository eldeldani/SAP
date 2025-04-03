#!/bin/bash

# Exit code
overall_exit_status=0
# Redirect everything to log file
current_date=$(date +%Y-%m-%d)
exec >> /tmp/sap_directories_housekeeping_$current_date.log 2>&1

##### Editable variables

# Different variables
# keep_days: The script will delete anything older than keep_days
# zip_days: The script will zip anything newer than keep_days and older than zip_days
keep_days=1825
zip_days=730
#zip_days=1780

# Array declaration for the file patterns to cleanup, You can edit by extending the patterns:
# i.e.: You wan to add the pattern *.gz you would append it to the end
# file_pattern_array=( OO* *.ARCHIVE FBI* gw_log* *.trc *.old.* *.old dev_* *.gz)
file_pattern_array=( OO* *.ARCHIVE FBI* gw_log* *.trc *.old.* *.old dev_* )


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
        echo -e "$(date): Script being executed in TEST mode."
else
        echo -e "$(date): Script being executed in EXECUTION mode."
fi
echo "$(date): SAP SIDs to analyze: ${sid_array[@]}"
echo "$(date): The following file patterns will be used: ${file_pattern_array[@]}"
echo "$(date): Files older than $keep_days days will be deleted"
echo "$(date): Files older than $zip_days days and newer than $keep_days days will be zipped"
echo "$(date): Files newer than $zip_days days will not be touched"

# Check for available compression tools
if command -v gzip &> /dev/null; then
    COMPRESS_TOOL="gzip"
elif command -v bzip2 &> /dev/null; then
    COMPRESS_TOOL="bzip2"
elif command -v xz &> /dev/null; then
    COMPRESS_TOOL="xz"
else
    echo -e "$(date): No suitable compression tool found."
    exit 1
fi

#Before filesystem usage loop
df -h |grep sap >> /tmp/before_fs_usage

#delete loop
files_to_delete_found="no"
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
                        files_to_delete=$(find $dir -maxdepth 1 -name "$pattern" -mtime +$keep_days -type f)
                        if [ -n "$files_to_delete" ]; then
				files_to_delete_found="yes"
				if [ "$1" != "execute" ]; then
                                	echo -e "$(date): The following files would be deleted on directory: $dir for pattern: $pattern if not in test mode, only listing..."
                                	find $dir -maxdepth 1 -name "$pattern" -mtime +$keep_days -type f -printf '%TY-%Tm-%Td %p\n' | sort -rn
                            	else
                                	echo -e "$(date): The following files will be deleted on directory: $dir for pattern: $pattern"
                                	find $dir -maxdepth 1 -name "$pattern" -mtime +$keep_days -type f -printf '%TY-%Tm-%Td %p\n' | sort -rn
                                	echo -e "$(date): Deleting the files..."
                                	find $dir -maxdepth 1 -name "$pattern" -mtime +$keep_days -type f -dddelete
                                	if ! [[ $? -eq 0 ]]; then
	                                    	echo -e "$(date): Error when deleting files"
	                                    	overall_exit_status=1
                                	fi
                            	fi	
				fi
                    done
            fi
        done
done
if [[ "$files_to_delete_found" = "no" ]]; then
	echo -e "$(date): No files found for deletion"
fi


#zip loop
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
                                                files_to_zip=$(find $dir -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -mtime -$keep_days -type f)
                                                if [ -n "$files_to_zip" ]; then
                                                        if [ "$1" != "execute" ]; then
                                                                echo -e "$(date): The following files would be zipped on directory: $dir for pattern: $pattern if not in test mode, only listing..."
                                                                find $dir -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -mtime -$keep_days -type f -printf '%TY-%Tm-%Td %p\n' | sort -rn                                                              
                                                        else
                                                                echo -e "$(date): The following files will be zipped on directory: $dir for pattern: $pattern"
                                                                find $dir -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -mtime -$keep_days -type f -printf '%TY-%Tm-%Td %p\n' | sort -rn
                                                                echo -e "$(date): Zipping files..."                                                                
                                                                case $COMPRESS_TOOL in
                                                                gzip)
                                                                    find $dir -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -mtime -$keep_days -type f -exec gzip {} \;
                                                                    if ! [[ $? -eq 0 ]]; then
                                                                        echo -e "$(date): Error when zipping files"
				                                                        overall_exit_status=1
                                                                    fi
                                                                    ;;
                                                                bzip2)
                                                                    find $dir -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -mtime -$keep_days -type f -exec bzip2 {} \;
                                                                    if ! [[ $? -eq 0 ]]; then
                                                                        echo -e "$(date): Error when zipping files"
				                                                        overall_exit_status=1
                                                                    fi
                                                                    ;;
                                                                xz)
                                                                    find $dir -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -mtime -$keep_days -type f -exec xz {} \;
                                                                    if ! [[ $? -eq 0 ]]; then
                                                                        echo -e "$(date): Error when zipping files"
				                                                        overall_exit_status=1
                                                                    fi
                                                                    ;;
                                                                esac
                                                        fi
                                                fi
                                        done
                        fi
        done
done

# After filesystem usage loop
df -h |grep sap >> /tmp/after_fs_usage

#Show Filesystem usage befor and after
echo -e "$(date): Filesystem usage before script:"
cat /tmp/before_fs_usage
echo -e "$(date): Filesystem usage after script:"
cat /tmp/after_fs_usage

#cleanup temporary files
rm /tmp/before_fs_usage /tmp/after_fs_usage

#Perform exit
exit $overall_exit_status
