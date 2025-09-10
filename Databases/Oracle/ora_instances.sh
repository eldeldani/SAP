#!/bin/bash

# Function to manage listener
function_listener() {
    ACTION=$1
    ORACLE_SID_LIST=$(cat /etc/oratab | grep -v '^#' |grep -v '^$' | awk -F: '{print $1}'|sort|uniq | awk -F: '{print $1}')
    for SID in $ORACLE_SID_LIST; 
    do
        # if [ "$SID" = "$2" ]
            export ORACLE_SID=$SID
            sid=${SID,,}
            # echo "SID: "$SID""
            ORACLE_LISTENER=$(su - ora"$sid" -c "grep -E '^L[a-zA-Z0-9]*[[:space:]]*=' \$ORACLE_HOME/network/admin/listener.ora | cut -d '=' -f 1")
            # echo "Found listener $ORACLE_LISTENER"
            case $ACTION in
                start)
                    echo "Starting listener..."
                    echo "SID: "$SID""
                    echo "Listener: "$ORACLE_LISTENER""
                    START=$(su - ora"$sid" -c "lsnrctl start "$ORACLE_LISTENER"")
                    echo "command: su - ora"$sid" -c "lsnrctl start "$ORACLE_LISTENER"""
                    if [[ $? -eq 0 ]]; then
                        echo "$START"
                    else
                        echo "Error stopping listener..."
                        exit 1
                    fi
                    ;;
                stop)
                    echo "Stopping listener..."
                    echo "SID: "$SID""
                    echo "Listener: "$ORACLE_LISTENER""
                    echo "command: su - ora"$sid" -c "lsnrctl stop "$ORACLE_LISTENER"""
                    STOP=$(su - ora"$sid" -c "lsnrctl stop "$ORACLE_LISTENER"")
                    if [[ $? -eq 0 ]]; then
                        echo "$STOP"
                    else
                        echo "Error stopping listener..."
                        exit 1
                    fi
                    ;;
                status)
                    echo "Checking listener status..."
                    echo "SID: "$SID""
                    echo "Listener: "$ORACLE_LISTENER""
                    echo "command: su - ora"$sid" -c "lsnrctl status "$ORACLE_LISTENER"""
                    STATUS=$(su - ora"$sid" -c "lsnrctl status "$ORACLE_LISTENER"")
                    if [[ $? -eq 0 ]]; then
                        echo "$STATUS"
                    else
                        echo "Error checking listener status..."
                        exit 1
                    fi
                    ;;
                list)
                    echo "Found listener..."
                    echo "SID: "$SID""
                    echo "Listener: "$ORACLE_LISTENER""
                    ;;
                *)
                    echo "We should not be here, invalid function_listener call without 'start', 'stop', 'status' or 'list' as arguments."
                    exit 1
                    ;;
            esac
        # fi
    done
}

# Function to manage Oracle instances
function_instance() {
    ACTION=$1
    ORACLE_SID_LIST=$(cat /etc/oratab | grep -v '^#' |grep -v '^$' | awk -F: '{print $1}'|sort|uniq | awk -F: '{print $1}')
    for SID in $ORACLE_SID_LIST; 
    do
        export ORACLE_SID=$SID
        sid=${SID,,}
        case $ACTION in
                start)
                    echo "Starting instance..."
                    echo "SID: "$SID""
                    INSTANCE_START=$(su - ora"$sid" -c '
                    sqlplus -s / as sysdba <<EOF
                    startup
                    EXIT;
                    EOF'
                    )
                    echo "$INSTANCE_START"
                    INSTANCE_STATUS=$(su - ora"$sid" -c '
                    sqlplus -s / as sysdba <<EOF
                    SET PAGESIZE 0
                    SET FEEDBACK OFF
                    SELECT * FROM v\$instance;
                    EXIT;
                    EOF'
                    )                              
                    if [[ $INSTANCE_STATUS == *"STARTED"* ]]; then
                        echo "Instance $SID is STARTED"
                    elif [[ $INSTANCE_STATUS == *"MOUNTED"* || $INSTANCE_STATUS == *"OPEN"* ]]; then
                        echo "Instance $SID is NOT STARTED"
                    fi
                    ;;
                stop)
                    echo "Stopping instance: "$SID"..."
                    INSTANCE_STOP=$(su - ora"$sid" -c '
                    sqlplus -s / as sysdba <<EOF
                    shu immediate
                    EXIT;
                    EOF'
                    )
                    echo "$INSTANCE_STOP"
                    INSTANCE_STATUS=$(su - ora"$sid" -c '
                    sqlplus -s / as sysdba <<EOF
                    SET PAGESIZE 0
                    SET FEEDBACK OFF
                    SELECT * FROM v\$instance;
                    EXIT;
                    EOF'
                    )                              
                    if [[ $INSTANCE_STATUS == *"STARTED"* ]]; then
                        echo "Instance $SID is STARTED"
                    elif [[ $INSTANCE_STATUS == *"MOUNTED"* || $INSTANCE_STATUS == *"OPEN"* ]]; then
                        echo "Instance $SID is NOT STARTED"
                    fi
                    ;;
                status)
                    echo "Checking instancer status..."
                    echo "SID: "$SID""
                    # echo "SID encontrada: "$sid""
                    INSTANCE_STATUS=$(su - ora"$sid" -c '
                    sqlplus -s / as sysdba <<EOF
                    SET PAGESIZE 0
                    SET FEEDBACK OFF
                    SELECT * FROM v\$instance;
                    EXIT;
                    EOF'
                    )                              
                    if [[ $INSTANCE_STATUS == *"STARTED"* ]]; then
                        echo "Instance $SID is STARTED"
                    elif [[ $INSTANCE_STATUS == *"MOUNTED"* ]]; then
                        echo "Instance "$SID" is MOUNTED"
                    elif [[ $INSTANCE_STATUS == *"OPEN"* ]]; then
                        echo "Instance $SID is OPEN"
                    else
                        echo "Instance $SID is SHUTDOWN"
                    fi
                    ;;
                list)
                    echo "Listing instances..."
                    echo "SID: "$SID""
                    ;;
                *)
                    echo "We should not be here, invalid function_listener call without 'start', 'stop', 'status' or 'list' as arguments."
                    exit 1
                    ;;
            esac
    done
}

function_all() {
    ACTION=$1
    ORACLE_SID_LIST=$(cat /etc/oratab | grep -v '^#' |grep -v '^$' | awk -F: '{print $1}'|sort|uniq | awk -F: '{print $1}')
    for SID in $ORACLE_SID_LIST; 
    do
        export ORACLE_SID=$SID
        sid=${SID,,}
        ORACLE_LISTENER=$(su - ora"$sid" -c "grep -E '^L[a-zA-Z0-9]*[[:space:]]*=' \$ORACLE_HOME/network/admin/listener.ora | cut -d '=' -f 1")
        case $ACTION in
                start)
                    echo "Starting instance..."
                    echo "SID: "$SID""
                    INSTANCE_START=$(su - ora"$sid" -c '
                    sqlplus -s / as sysdba <<EOF
                    startup
                    EXIT;
                    EOF'
                    )
                    echo "$INSTANCE_START"
                    INSTANCE_STATUS=$(su - ora"$sid" -c '
                    sqlplus -s / as sysdba <<EOF
                    SET PAGESIZE 0
                    SET FEEDBACK OFF
                    SELECT * FROM v\$instance;
                    EXIT;
                    EOF'
                    )                              
                    if [[ $INSTANCE_STATUS == *"STARTED"* ]]; then
                        echo "Instance $SID is STARTED"
                    elif [[ $INSTANCE_STATUS == *"MOUNTED"* || $INSTANCE_STATUS == *"OPEN"* ]]; then
                        echo "Instance $SID is NOT STARTED"
                    fi
                    ;;
                stop)
                    echo "Stopping instance: "$SID"..."
                    INSTANCE_STOP=$(su - ora"$sid" -c '
                    sqlplus -s / as sysdba <<EOF
                    shu immediate
                    EXIT;
                    EOF'
                    )
                    echo "$INSTANCE_STOP"
                    INSTANCE_STATUS=$(su - ora"$sid" -c '
                    sqlplus -s / as sysdba <<EOF
                    SET PAGESIZE 0
                    SET FEEDBACK OFF
                    SELECT * FROM v\$instance;
                    EXIT;
                    EOF'
                    )                              
                    if [[ $INSTANCE_STATUS == *"STARTED"* ]]; then
                        echo "Instance $SID is STARTED"
                    elif [[ $INSTANCE_STATUS == *"MOUNTED"* || $INSTANCE_STATUS == *"OPEN"* ]]; then
                        echo "Instance $SID is NOT STARTED"
                    fi
                    ;;
                status)
                    echo "Checking instancer status..."
                    echo "SID: "$SID""
                    # echo "SID encontrada: "$sid""
                    INSTANCE_STATUS=$(su - ora"$sid" -c '
                    sqlplus -s / as sysdba <<EOF
                    SET PAGESIZE 0
                    SET FEEDBACK OFF
                    SELECT * FROM v\$instance;
                    EXIT;
                    EOF'
                    )                              
                    if [[ $INSTANCE_STATUS == *"STARTED"* ]]; then
                        echo "Instance $SID is STARTED"
                    elif [[ $INSTANCE_STATUS == *"MOUNTED"* ]]; then
                        echo "Instance "$SID" is MOUNTED"
                    elif [[ $INSTANCE_STATUS == *"OPEN"* ]]; then
                        echo "Instance $SID is OPEN"
                    else
                        echo "Instance $SID is SHUTDOWN"
                    fi
                    ;;
                list)
                    echo "Listing Oracle instances..."
                    echo "Oracle SID: "$SID""
                    echo "Listener: "$ORACLE_LISTENER""
                    ;;
                *)
                    echo "We should not be here, invalid function_listener call without 'start', 'stop', 'status' or 'list' as arguments."
                    exit 1
                    ;;
            esac
    done
}


#         if [[ $INSTANCE_STATUS == *"STARTED"* ]]; then
#             # if [ "$ACTION" == "stop" ]; then
#                 echo "Instance $SID is STARTED"
# #                 sqlplus -s / as sysdba <<EOF
# # SHUTDOWN IMMEDIATE;
# # EXIT;
# # EOF
#             # fi
# #        elif [[ $INSTANCE_STATUS == *"MOUNTED"* || $INSTANCE_STATUS == *"OPEN"* ]]; then
# # #             if [ "$ACTION" == "start" ]; then
# #                 echo "Instance $SID is NOT STARTED"
# # # #                 sqlplus -s / as sysdba <<EOF
# # # STARTUP;
# # # EXIT;
# # # EOF
# #             fi
#         fi
#     done


# Manage listener



# manage_listener

# Manage Oracle instances
# manage_instances

case $1 in
    listener)
        if [[ "$2" == "list" || "$2" == "stop" || "$2" == "start" || "$2" == "status" ]]; then
        function_listener $2
        else 
            echo "Error: argument 'all' requires 'list', 'status', 'stop' or 'start'"
            exit 1
        fi
        ;;
    instance)
        if [[ "$2" == "list" || "$2" == "stop" || "$2" == "start" || "$2" == "status" ]]; then
        function_instance $2
        else 
            echo "Error: argument 'all' requires 'list', 'status', 'stop' or 'start'"
            exit 1
        fi
        ;;
    all)
        if [[ "$2" == "list" || "$2" == "stop" || "$2" == "start" || "$2" == "status" ]]; then
        function_all $2
        else 
            echo "Error: argument 'all' requires 'list', 'status', 'stop' or 'start'."
            exit 1
        fi
        ;;
    *)
        echo "Error: 'command' must be 'listener', 'instance' or 'all'."
        exit 1
        ;;
esac