#!/bin/bash

# Directory where SAP instances are stored (modify this according to your setup)
SAP_INSTANCE_DIR="/usr/sap"
overall_exit_status=0  # Initialize overall exit status


exec > /dev/null 2>&1


# Loop through each SID directory
for sid in $(ls $SAP_INSTANCE_DIR); do
	# Convert SID to lowercase
    sid_lower=${sid,,}
    
	# Loop through each instance directory for the SID based on the specified patterns
    for instance_dir in $(ls $SAP_INSTANCE_DIR/$sid | grep -E '^(D|DVEBMGS|ASCS|SCS|J|SMDA)[0-9]{2}$'); do
        # Extract the instance number from the directory name
        instance_number=${instance_dir##*[D|DVEBMGS|ASCS|SCS|J]}

        # Check if the instance number is valid (using pattern matching)
        if [[ "$instance_number" =~ ^[0-9]+$ ]]; then
            # Execute sapcontrol command as the SAP administrator user
            echo "Executing command for SID: $sid, Instance Number: $instance_number"
            su - ${sid_lower}"adm" -c "sapcontrol -nr $instance_number -function GetProcessList"
			#result=$(su - ${sid_lower}"adm" -c "sapcontrol -nr $instance_number -function GetProcessList")
			# Check the result and output accordingly
			if ! [[ $? -eq 3 ]]; then
				#echo "Result for SID: $sid Instance Number: $instance_number is not 3"
				overall_exit_status=1  # Set overall exit status to 1 if any result is not 3
			fi
			
		fi
    done
done
exit $overall_exit_status  # Exit with the overall status
