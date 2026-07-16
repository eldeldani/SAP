#!/bin/bash

function_oracle_listener() {
    # Variables
    local SID ACTION ORA_USER LISTENER_NAME RC
    SID="$1"
    ACTION="$2"
    # Validate number of arguments
    [ $# -ne 2 ] && {
        echo "ERROR: Usage: function_oracle_listener <SID> <check|start|stop>"
        return 1
    }
    # Validate ACTION argument
    case "$ACTION" in
        check|start|stop) ;;
        *)
            echo "ERROR: Invalid action '$ACTION'"
            return 1
            ;;
    esac
    # Validate SID format (exactly 3 alphanumeric characters)
    [[ ! "$SID" =~ ^[A-Z0-9]{3}$ ]] && {
        echo "ERROR: SID must be exactly 3 alphanumeric characters"
        return 2
    }   

    # Convert SID to uppercase, ACTION to lowercase, and construct ORA_USER in lowercase
    SID="$(echo "$SID" | tr '[:lower:]' '[:upper:]')"
    ACTION="$(echo "$ACTION" | tr '[:upper:]' '[:lower:]')"
    ORA_USER="ora$(echo "$SID" | tr '[:upper:]' '[:lower:]')"    
    
    # Retrieve the listener name from the listener.ora file, defaulting to 'LISTENER' if not found
    # LISTENER_NAME=$(su - "$ORA_USER" -c "grep -i '^[[:blank:]]*listener_*[[:alpha:]]*[[:blank:]]*=' \"\$ORACLE_HOME/network/admin/listener.ora\" | awk '{ print \$1 }' | sed 's/=//g'")
    LISTENER_NAME=$(su - "$ORA_USER" -c "grep -iE '^[[:blank:]]*[[:alpha:]_][[:alnum:]_]*[[:blank:]]*=[[:blank:]]*\$' \"\$ORACLE_HOME/network/admin/listener.ora\" | grep -vi '^[[:blank:]]*SID' | awk -F= '{gsub(/[[:blank:]]/, \"\", \$1); print \$1}' | head -1")
    [ -z "$LISTENER_NAME" ] && LISTENER_NAME='LISTENER'
    
    # Uncomment the following line for debugging purposes
    # echo "variables: SID=$SID, ACTION=$ACTION, ORA_USER=$ORA_USER, LISTENER_NAME=$LISTENER_NAME"

    # Main logic to perform the specified action on the Oracle listener
    case "$ACTION" in
            check)
                # echo "Checking status of listener '$LISTENER_NAME' for SID '$SID'..."
                su - "$ORA_USER" -c "lsnrctl status ${LISTENER_NAME}"
                ;;
            start)
                # echo "Starting listener '$LISTENER_NAME' for SID '$SID'..."
                su - "$ORA_USER" -c "lsnrctl start ${LISTENER_NAME}"
                ;;
            stop)
                # echo "Stopping listener '$LISTENER_NAME' for SID '$SID'..."
                su - "$ORA_USER" -c "lsnrctl stop ${LISTENER_NAME}"
                ;;
        esac
    RC=$?
    return $RC
}

if [ $# -ne 2 ]; then
    echo "Usage: $0 <SID> <check|start|stop>"
    exit 1
fi

function_oracle_listener "$1" "$2"

RC=$?

exit $RC
