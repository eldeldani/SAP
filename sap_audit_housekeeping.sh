#!/bin/bash
# 
# Exit code
overall_exit_status=0
# Redirect everything to log file
current_date=$(date +%Y-%m-%d)
# exec >> /tmp/sap_audit_housekeeping_$current_date.log 2>&1

##### Editable variables

# Different variables
# zip_days: The script will zip anything newer than keep_days and older than zip_days
# zip_days=730
zip_days=50

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


#### Output summary before execution
echo "======================================================================="
echo "$(date): Script started in $HOSTNAME"
if [ "$1" != "execute" ]; then
        echo -e "$(date): Script being executed in TEST mode."
else
        echo -e "$(date): Script being executed in EXECUTION mode."
fi
echo "$(date): The following file patterns will be used: ${file_pattern_array[@]}"
echo "$(date): Files older than $zip_days days will be zipped"


length=${#sap_instances_array[@]}
echo "sap_instances_array Array length: $length"
for (( i=0; i<(${length}); i+=5 ));
do 
    echo -e "Working on:\n${sap_instances_array[$i]} --> ${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]}"
    var=$(grep DIR_AUDIT /sapmnt/${sap_instances_array[$i]}/profile/${sap_instances_array[$i+1]}_${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}_${sap_instances_array[$i+4]} | grep DIR_AUDIT |awk '{ print $3 }')
    if ! [[ -n $var ]]; then
	    echo "Parameter not defined in instance profile, looking in DEFAULT.PFL"
        var=$(grep DIR_AUDIT /sapmnt/${sap_instances_array[$i]}/profile/DEFAULT.PFL | grep DIR_AUDIT |awk '{ print $3 }')
        if ! [[ -n $var ]]; then
            echo "Parameter not defined in DEFAULT.PFL, using kernel's default"
            var=/usr/sap/${sap_instances_array[$i]}/${sap_instances_array[$i+2]}${sap_instances_array[$i+3]}/log
        fi
    fi
    echo "Will look in directory: $var"
    for pattern in ${file_pattern_array[@]}
    do
        echo "Pattern: $pattern"
        files_to_zip=$(find $var -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -type f)
        if [ -n "$files_to_zip" ]; then
            if [ "$1" != "execute" ]; then
                    echo -e "$(date): The following files would be zipped on directory: $var for pattern: $pattern if not in test mode, only listing..."
                    find $var -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -type f -printf '%TY-%Tm-%Td %p\n' | sort -rn                                                              
            else
                    echo -e "$(date): The following files will be zipped on directory: $var for pattern: $pattern"
                    find $var -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -type f -printf '%TY-%Tm-%Td %p\n' | sort -rn
                    echo -e "$(date): Zipping files..."                                                                
                    case $COMPRESS_TOOL in
                    gzip)
                        # find $dir -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -type f -exec gzip {} \;
                        if ! [[ $? -eq 0 ]]; then
                            echo -e "$(date): Error when zipping files"
                            overall_exit_status=1
                        fi
                        ;;
                    bzip2)
                        # find $dir -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -type f -exec bzip2 {} \;
                        if ! [[ $? -eq 0 ]]; then
                            echo -e "$(date): Error when zipping files"
                            overall_exit_status=1
                        fi
                        ;;
                    xz)
                        # find $dir -maxdepth 1 -name "$pattern" ! -name "*.gz" ! -name "*.bz2" ! -name "*.xz" -mtime +$zip_days -type f -exec xz {} \;
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

echo $overall_exit_status


