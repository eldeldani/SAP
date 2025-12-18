#!/bin/bash
# SAP standard directories houskeeping script
# Created by Daniel Munoz
# Usage:
# sap_directory_housekeeping.sh [execution]
#   If executed with arguments, it will just perform analysis without any action.
#   If executed with 'execution' argument, it will perform actions below.
#   The script will look in to the following directories:
        # global=/usr/sap/$sap_sid/SYS/global
        # work_ascs=/usr/sap/$sap_sid/ASCS[0-9][0-9]/work
        # work_scs=/usr/sap/$sap_sid/SCS[0-9][0-9]/work
        # work_ci=/usr/sap/$sap_sid/DVEBMGS[0-9][0-9]/work
        # work_dia=/usr/sap/$sap_sid/D[0-9][0-9]/work
        # work_java=/usr/sap/$sap_sid/J[0-9][0-9]/work
    # You can extend the directory lookup by adding more paths after section "# (modifiable section) modify paths"

# File patterns: "# (modifiable section) modify file patterns"
#   The script will look for the following file patterns/names by default:
#       file_pattern_array=( OO* *.ARCHIVE FBI* gw_log* *.trc *.old.* *.old dev_* )
#   
# Retention days: "# (modifiable section) modify retention"
#   keep_days = The script will delete anything older than keep_days
#   zip_days = The script will zip anything newer than keep_days and older than zip_days
#   365 = 1 Year, 730 = 2 Years, 1095 = 3 Years, 1460 = 4 Years, 1825 = 5 Years, 3650 = 10 Years

# Script will produce a log on /tmp/sap_directories_housekeeping_<date>.log

# (modifiable section) modify retention
keep_days=1825
zip_days=730
#zip_days=1780

# Exit code
overall_exit_status=0
# Redirect everything to log file
current_date=$(date +%Y-%m-%d)
exec >> /tmp/sap_directories_housekeeping_$current_date.log 2>&1





# (modifiable section) modify file patterns
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

# # Temporarily redirecting both to standard output and file
# {
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
# } | tee /dev/tty
# # // Temporarily redirecting both to standard output and file

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

#Before filesystem usage
df -h |grep sap |sort|uniq >> /tmp/before_fs_usage
    


#delete loop
files_to_delete_found="no"
for sap_sid in ${sid_array[@]}
do
        # (modifiable section) modify paths
        global=/usr/sap/$sap_sid/SYS/global
        work_ascs=/usr/sap/$sap_sid/ASCS[0-9][0-9]/work
        work_scs=/usr/sap/$sap_sid/SCS[0-9][0-9]/work
        work_ci=/usr/sap/$sap_sid/DVEBMGS[0-9][0-9]/work
        work_dia=/usr/sap/$sap_sid/D[0-9][0-9]/work
        work_java=/usr/sap/$sap_sid/J[0-9][0-9]/work
        
        # (modifiable section) modify paths
        # If you have added new paths, add them in the paths_array below
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
                                	find $dir -maxdepth 1 -name "$pattern" -mtime +$keep_days -type f -delete
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

# # Temporarily redirecting both to standard output and file
# {
if [[ "$files_to_delete_found" = "no" ]]; then
	echo -e "$(date): No files found for deletion"
fi
# } | tee /dev/tty
# #  //Temporarily redirecting both to standard output and file


#zip loop
files_to_zip_found="no"
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
                                                    files_to_zip_found="yes"
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
# # Temporarily redirecting both to standard output and file
# {
if [[ "$files_to_zip_found" = "no" ]]; then
	echo -e "$(date): No files found to zip"
fi
# } | tee /dev/tty
# # // Temporarily redirecting both to standard output and file

# After filesystem usage
df -h |grep sap |sort|uniq >> /tmp/after_fs_usage

#Show Filesystem usage before and after
if [ "$files_to_zip_found" = "yes" ] || [ "$files_to_delete_found" = "yes" ]; then
    echo -e "$(date): Filesystem usage before script:"
    cat /tmp/before_fs_usage
    echo -e "$(date): Filesystem usage after script:"
    cat /tmp/after_fs_usage
fi
#cleanup temporary files
rm /tmp/before_fs_usage /tmp/after_fs_usage
exec 1>&1
exec 2>&2

# Cleanup logs older than 60 days
find /tmp/ -name "sap_directories_housekeeping_*.log" -type f -mtime +60 -exec rm {} \;

# # Temporarily redirecting both to standard output and file
# {
if [ "$overall_exit_status" -eq 0 ]; then
    echo -e "$(date): Script completed successfully. Check log /tmp/sap_directories_housekeeping_$current_date.log for more details."
else
    echo -e "$(date): Script executed with errors, please check log /tmp/sap_directories_housekeeping_$current_date.log"
fi
# } | tee /dev/tty
# #  //Temporarily redirecting both to standard output and file

#Perform exit
exit $overall_exit_status
