#!/bin/bash
# SAP standard audit directories houskeeping script
# Created by Daniel Munoz
# Usage:
# sap_audit_housekeeping.sh [execution]
#   
# zip_days: The script will zip anything newer than keep_days and older than zip_days. Go to "modifiable section" to adapt it
#   zip_days = The script will zip anything newer than keep_days and older than zip_days
#   365 = 1 Year, 730 = 2 Years, 1095 = 3 Years, 1460 = 4 Years, 1825 = 5 Years, 3650 = 10 Years
#
# File patterns: "# (modifiable section) modify file patterns"
#   The script will look for the following file patterns/names by default:
#       file_pattern_array=( audit* )
#
# Script will produce a log on /tmp/sap_audit_housekeeping_<date>.log

# Exit code
overall_exit_status=0
# Redirect everything to log file
current_date=$(date +%Y-%m-%d)
exec >> /tmp/sap_audit_housekeeping_$current_date.log 2>&1

# (modifiable section)
# zip_days: The script will zip anything newer than keep_days and older than zip_days
zip_days=730

# Array declaration for the file patterns to cleanup, You can edit by extending the patterns:
# i.e.: You wan to add the pattern *.gz you would append it to the end
# file_pattern_array=( OO* *.ARCHIVE FBI* gw_log* *.trc *.old.* *.old dev_* *.gz)
file_pattern_array=( audit* )


## Initialize an array with unique SAP SIDs
declare -a hostname_array
declare -a sid_array
declare -a sap_instances_array
# Read each line from the file
while IFS= read -r line; do
    # Use a regular expression to extract the required part
    # if [[ $line =~ (\/usr\/sap\/)([a-zA-Z0-9]{3})*([a-zA-Z0-9]{3,5})_(D|DVEBMGS|ASCS|SCS|J|SMDA)([0-9]{2})_([a-zA-Z0-9]{1,13}) ]]; then
    if [[ $line =~ /usr/sap/([a-zA-Z0-9]{3})/SYS/profile/([a-zA-Z0-9]{3,5})_(D|DVEBMGS)([0-9]{2})_([a-zA-Z0-9]{1,13}) ]]; then
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
        sid_array+=("$SID")
    fi
done < "/usr/sap/sapservices"  # Replace "your_file.txt" with the actual filename


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

#### Output summary before execution
echo "======================================================================="
echo "$(date): Script started in $HOSTNAME"
if [ "$1" != "execute" ]; then
        echo -e "$(date): Script being executed in TEST mode."
else
        echo -e "$(date): Script being executed in EXECUTION mode."
fi
if [ ${#sap_instances_array[@]} -lt 1 ]; then
    echo "$(date): No suitable SAP instances found for audit cleanup. Exiting..."
    exit 0
else
    echo "$(date): The following file patterns will be used: ${file_pattern_array[@]}"
    echo "$(date): Files older than $zip_days days will be zipped"
    echo "$(date): Files will be zipped with "$COMPRESS_TOOL""
fi

#defining original variable value
files_to_zip_found="no"

#zip loop
length=${#sap_instances_array[@]}
# echo "sap_instances_array Array length: $length"
for (( i=0; i<(${length}); i+=5 ));
do 
    echo -e "$(date): Working on: ${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
    echo -e "$(date): Looking for DIR_AUDIT parameter"
    var=$(grep DIR_AUDIT /sapmnt/${sap_instances_array[$i]}/profile/${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]} | grep DIR_AUDIT |awk '{ print $3 }')
    if ! [[ -n $var ]]; then
	    echo "$(date): Parameter not defined in instance profile, looking in DEFAULT.PFL"
        var=$(grep DIR_AUDIT /sapmnt/${sap_instances_array[$i]}/profile/DEFAULT.PFL | grep DIR_AUDIT |awk '{ print $3 }')
        if ! [[ -n $var ]]; then
            echo "$(date): Parameter not defined in DEFAULT.PFL, using kernel's default"
            var=/usr/sap/${sap_instances_array[$i]}/${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}/log
        else
            echo -e "$(date): Parameter DIR_AUDIT found in DEFAULT profile with value: $var"
        fi
    else
        echo -e "$(date): Parameter DIR_AUDIT found in instance profile with value: $var"
    fi
    for pattern in ${file_pattern_array[@]}
    do
        files_to_zip=$(find $var -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -type f)
        if [ -n "$files_to_zip" ]; then
            # Files are found, we set variable
            files_to_zip_found="yes"
            if [ "$1" != "execute" ]; then
                    echo -e "$(date): The following files would be zipped on directory: $var for pattern: $pattern if not in test mode, only listing..."
                    find $var -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -type f -printf '%TY-%Tm-%Td %p\n' | sort -rn                                                              
            else
                    echo -e "$(date): The following files will be zipped on directory: $var for pattern: $pattern"
                    find $var -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -type f -printf '%TY-%Tm-%Td %p\n' | sort -rn
                    echo -e "$(date): Zipping files..."                                                                
                    case $COMPRESS_TOOL in
                    gzip)
                        find $var -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -type f -exec gzip {} \;
                        echo -e "$(date): Compressing with "$COMPRESS_TOOL""
                        if ! [[ $? -eq 0 ]]; then
                            echo -e "$(date): Error when zipping files"
                            overall_exit_status=1
                        fi
                        ;;
                    bzip2)
                        echo -e "$(date): Compressing with "$COMPRESS_TOOL""
                        find $var -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -type f -exec bzip2 {} \;
                        if ! [[ $? -eq 0 ]]; then
                            echo -e "$(date): Compressing with "$COMPRESS_TOOL""
                            overall_exit_status=1
                        fi
                        ;;
                    xz)
                        echo -e "$(date): Compressing with "$COMPRESS_TOOL""
                        find $var -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -type f -exec xz {} \;
                        if ! [[ $? -eq 0 ]]; then
                            echo -e "$(date): Error when zipping files"
                            overall_exit_status=1
                        fi
                        ;;
                    esac
            fi
        fi
    done
done

if [[ "$files_to_zip_found" = "no" ]]; then
	echo -e "$(date): No files found to zip"
fi

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

if [ "$overall_exit_status" -eq 0 ]; then
    echo -e "$(date): Script completed successfully. Check log /tmp/sap_audit_housekeeping_$current_date.log for more details."
else
    echo -e "$(date): Script executed with errors, please check log /tmp/sap_audit_housekeeping_$current_date.log"
fi

#Perform exit
exit $overall_exit_status


