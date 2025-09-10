#!/bin/bash

# Configuration
TRANS_LIST_FILE="/usr/sap/trans/bin/transport_list.txt" # Path to the file with TR numbers
SAP_SID="$1"  # Replace with your SAP system ID
SAP_CLIENT="$2"           # Replace with your client number
TP_DOMAIN_PROFILE="/usr/sap/trans/bin/TP_DOMAIN_$SAP_SID.PFL"

# Loop through each transport request in the file
while read -r transport_request; do
    echo "Adding transport request: $transport_request to buffer"
    tp addtobuffer "$transport_request" "$SAP_SID" client=$SAP_CLIENT pf="$TP_DOMAIN_PROFILE"
done < "$TRANS_LIST_FILE"

echo "All transport requests added to buffer."