#!/usr/bin/env bash
# SAP instance and database management script.

LOG_FILE="/tmp/sap_instances.sh.log"
SAPSERVICES="/usr/sap/sapservices"
SAPHOSTCTRL="/usr/sap/hostctrl/exe/saphostctrl"

# 1 = simulate disruptive commands; 0 = execute them.
declare -i testexec=1

exec > >(tee -a "$LOG_FILE") 2>&1

declare -a sap_systems_array=()
declare -a db_systems_array=()
declare -a sap_instances_all_array=()
declare -a sap_abap_instances_array=()
declare -a sap_java_instances_array=()
declare -a sap_hdb_instances_array=()
declare -a sap_contentserver_instances_array=()
declare -a sap_ascs_instances_array=()
declare -a sap_scs_instances_array=()

declare -A db_types_cache=()

declare -i sap_instances_found=0
declare -i db_systems_found=0

log() {
    printf '%(%F %T)T: %s\n' -1 "$*"
}

trim() {
    local value=$1
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s' "$value"
}

contains() {
    local needle=$1
    shift

    local value
    for value in "$@"; do
        [[ $value == "$needle" ]] && return 0
    done

    return 1
}

add_unique_value() {
    local array_name=$1
    local value=$2
    local -n target_array=$array_name

    contains "$value" "${target_array[@]}" || target_array+=("$value")
}

append_instance() {
    local array_name=$1
    local -n target_array=$array_name

    target_array+=("$2" "$3" "$4" "$5" "$6")
}

instance_description() {
    case $1 in
        D)       printf 'Dialog Instance' ;;
        DVEBMGS) printf 'Dialog Central Instance' ;;
        ASCS)    printf 'ABAP Central Services Instance' ;;
        SCS)     printf 'JAVA Central Services Instance' ;;
        J)       printf 'JAVA Instance' ;;
        C)       printf 'Content Server' ;;
        HDB)     printf 'SAP HANA Database Instance' ;;
        *)       printf 'Unknown Instance Type' ;;
    esac
}

db_type_friendly_name() {
    case ${1,,} in
        hdb)     printf 'SAP HANA' ;;
        ora)     printf 'Oracle' ;;
        db2)     printf 'IBM DB2' ;;
        syb)     printf 'SAP ASE (Sybase)' ;;
        ada|sap) printf 'MaxDB' ;;
        *)       printf 'Unknown' ;;
    esac
}

instance_label() {
    local array_name=$1
    local index=$2
    local -n records=$array_name

    printf '%s --> %s_%s%s_%s' \
        "${records[index]}" \
        "${records[index + 1]}" \
        "${records[index + 2]}" \
        "${records[index + 3]}" \
        "${records[index + 4]}"
}

run_readonly_as_sidadm() {
    local sid=${1,,}
    local command=$2

    su - "${sid}adm" -c "$command"
}

run_disruptive_command() {
    local description=$1
    shift

    log "Command: $description"

    if ((testexec)); then
        log "[TEST MODE] Command not executed: $description"
        return 0
    fi

    "$@"
}

run_disruptive_as_sidadm() {
    local sid=${1,,}
    local command=$2

    run_disruptive_command \
        "su - ${sid}adm -c \"$command\"" \
        su - "${sid}adm" -c "$command"
}

find_sap_instances() {
    local line
    local sid
    local profile
    local type
    local number
    local hostname

    [[ -f $SAPSERVICES ]] || {
        log "! Error: file not found: $SAPSERVICES"
        return 1
    }

    while IFS= read -r line; do
        [[ $line == \#* ]] && continue

        [[ $line =~ /usr/sap/([[:alnum:]]{3})/SYS/profile/([[:alnum:]]{3,5})_(D|DVEBMGS|ASCS|SCS|J|C|HDB)([0-9]{2})_([[:alnum:]-]+) ]] || continue

        sid=${BASH_REMATCH[1]}
        profile=${BASH_REMATCH[2]}
        type=${BASH_REMATCH[3]}
        number=${BASH_REMATCH[4]}
        hostname=${BASH_REMATCH[5]}

        append_instance sap_instances_all_array \
            "$sid" "$profile" "$type" "$number" "$hostname"

        add_unique_value sap_systems_array "$sid"
        sap_instances_found=1

        case $type in
            D|DVEBMGS)
                append_instance sap_abap_instances_array \
                    "$sid" "$profile" "$type" "$number" "$hostname"
                ;;
            J)
                append_instance sap_java_instances_array \
                    "$sid" "$profile" "$type" "$number" "$hostname"
                ;;
            HDB)
                append_instance sap_hdb_instances_array \
                    "$sid" "$profile" "$type" "$number" "$hostname"
                ;;
            C)
                append_instance sap_contentserver_instances_array \
                    "$sid" "$profile" "$type" "$number" "$hostname"
                ;;
            ASCS)
                append_instance sap_ascs_instances_array \
                    "$sid" "$profile" "$type" "$number" "$hostname"
                ;;
            SCS)
                append_instance sap_scs_instances_array \
                    "$sid" "$profile" "$type" "$number" "$hostname"
                ;;
        esac
    done < "$SAPSERVICES"
}

find_db_systems() {
    local output
    local line
    local current_db_name=""
    local db_name
    local db_type_code

    [[ -x $SAPHOSTCTRL ]] || {
        log "! Error: executable not found: $SAPHOSTCTRL"
        return 1
    }

    output=$("$SAPHOSTCTRL" -function ListDatabaseSystems 2>&1) || {
        log "! Error: unable to list database systems."
        return 1
    }

    while IFS= read -r line; do
        if [[ $line =~ Database[[:space:]]name:[[:space:]]*([^,\ ]+) ]]; then
            db_name=${BASH_REMATCH[1]^^}

            if [[ $db_name == *@* ]]; then
                current_db_name=""
            else
                current_db_name=$db_name
                add_unique_value db_systems_array "$db_name"
            fi
        fi

        if [[ -n $current_db_name &&
              $line =~ Type:[[:space:]]*([^,\ ]+) ]]; then
            db_type_code=${BASH_REMATCH[1]}
            db_types_cache["$current_db_name"]=$db_type_code
        fi
    done <<< "$output"

    ((${#db_systems_array[@]} > 0)) && db_systems_found=1
}

db_type() {
    local db_name=${1^^}

    if [[ -n ${db_types_cache[$db_name]:-} ]]; then
        printf '%s\n' "${db_types_cache[$db_name]}"
        return 0
    fi

    return 1
}

oracle_listener() {
    local sid=${1^^}
    local action=${2,,}
    local ora_user
    local listener_name
    local discovery_command
    local listener_command

    [[ $# -eq 2 ]] || {
        log "! Error: usage: oracle_listener <SID> <check|start|stop>"
        return 1
    }

    [[ $sid =~ ^[A-Z0-9]{3}$ ]] || {
        log "! Error: Oracle SID must be exactly three alphanumeric characters."
        return 1
    }

    case $action in
        check|start|stop) ;;
        *)
            log "! Error: invalid Oracle listener action '$action'."
            return 1
            ;;
    esac

    ora_user="ora${sid,,}"

    id "$ora_user" &>/dev/null || {
        log "! Error: Oracle user '$ora_user' does not exist."
        return 1
    }

    discovery_command='
        listener_file="$ORACLE_HOME/network/admin/listener.ora"

        if [[ -r $listener_file ]]; then
            awk -F= '"'"'
                /^[[:space:]]*[[:alpha:]_][[:alnum:]_]*[[:space:]]*=[[:space:]]*\(/ {
                    name = $1
                    gsub(/[[:space:]]/, "", name)

                    if (toupper(name) !~ /^SID/ && toupper(name) !~ /^DEFAULT/) {
                        print name
                        exit
                    }
                }
            '"'"' "$listener_file"
        fi
    '

    log "Command: su - $ora_user -c \"Oracle listener discovery from \$ORACLE_HOME/network/admin/listener.ora\""

    listener_name=$(su - "$ora_user" -c "$discovery_command" 2>/dev/null)
    listener_name=$(trim "$listener_name")
    [[ -n $listener_name ]] || listener_name="LISTENER"

    listener_command="lsnrctl $action $listener_name"

    case $action in
        check)
            log "Checking Oracle listener '$listener_name' for SID '$sid'."
            log "Command: su - $ora_user -c \"$listener_command\""
            su - "$ora_user" -c "$listener_command"
            ;;
        start)
            log "Starting Oracle listener '$listener_name' for SID '$sid'."

            run_disruptive_command \
                "su - $ora_user -c \"$listener_command\"" \
                su - "$ora_user" -c "$listener_command"
            ;;
        stop)
            log "Stopping Oracle listener '$listener_name' for SID '$sid'."

            run_disruptive_command \
                "su - $ora_user -c \"$listener_command\"" \
                su - "$ora_user" -c "$listener_command"
            ;;
    esac
}

db_get_status() {
    local db_name=${1^^}
    local db_type_code=$2
    local output
    local line
    local lower_line
    local status

    output=$(
        "$SAPHOSTCTRL" \
            -function GetDatabaseStatus \
            -dbname "$db_name" \
            -dbtype "$db_type_code" 2>&1
    ) || return 1

    while IFS= read -r line; do
        lower_line=${line,,}

        if [[ $lower_line =~ ^[[:space:]]*database[[:space:]]+status[[:space:]]*:[[:space:]]*(.+)$ ||
              $lower_line =~ ^[[:space:]]*status[[:space:]]*:[[:space:]]*(.+)$ ]]; then
            status=$(trim "${BASH_REMATCH[1]}")
            status=${status%%,*}
            printf '%s\n' "${status^^}"
            return 0
        fi
    done <<< "$output"

    return 1
}

db_list() {
    local db_name
    local db_type_code
    local db_type_name

    ((db_systems_found)) || {
        log "No database instances found."
        return 1
    }

    for db_name in "${db_systems_array[@]}"; do
        if db_type_code=$(db_type "$db_name"); then
            db_type_name=$(db_type_friendly_name "$db_type_code")
            log "$db_name --> $db_type_name Database"
        else
            log "$db_name --> Unknown Database"
        fi
    done
}

db_status_one() {
    local db_name=${1^^}
    local db_type_code
    local db_type_name
    local status

    db_type_code=$(db_type "$db_name") || {
        log "UNKNOWN - $db_name --> Unknown Database"
        return 1
    }

    db_type_name=$(db_type_friendly_name "$db_type_code")

    if status=$(db_get_status "$db_name" "$db_type_code"); then
        log "$status - $db_name --> $db_type_name Database"
        return 0
    fi

    log "UNKNOWN - $db_name --> $db_type_name Database"
    return 1
}

db_status() {
    local requested_db=${1^^}
    local db_name
    local status=0

    ((db_systems_found)) || {
        log "No database instances found."
        return 1
    }

    if [[ -z $requested_db || $requested_db == ALL || $requested_db == NONE ]]; then
        for db_name in "${db_systems_array[@]}"; do
            db_status_one "$db_name" || status=1
        done

        return "$status"
    fi

    db_status_one "$requested_db"
}

db_status_det_one() {
    local db_name=${1^^}
    local db_type_code
    local db_type_name
    local result
    local line

    db_type_code=$(db_type "$db_name") || {
        log "! Error: database '$db_name' was not found."
        return 1
    }

    db_type_name=$(db_type_friendly_name "$db_type_code")
    log "=== Detailed database status: $db_name --> $db_type_name Database"

    result=$(
        "$SAPHOSTCTRL" \
            -function GetDatabaseStatus \
            -dbname "$db_name" \
            -dbtype "$db_type_code" 2>&1
    ) || {
        log "! Error: unable to retrieve status for database '$db_name'."
        return 1
    }

    while IFS= read -r line; do
        log "$line"
    done <<< "$result"
}

db_status_det() {
    local requested_db=${1^^}
    local db_name
    local status=0

    ((db_systems_found)) || {
        log "No database instances found."
        return 1
    }

    if [[ -z $requested_db || $requested_db == ALL || $requested_db == NONE ]]; then
        for db_name in "${db_systems_array[@]}"; do
            db_status_det_one "$db_name" || status=1
            log "===================================================="
        done

        return "$status"
    fi

    db_status_det_one "$requested_db"
}

db_status_for_sid() {
    local sid=${1^^}

    if contains "$sid" "${db_systems_array[@]}"; then
        db_status_one "$sid"
    else
        log "Database: none registered for SID $sid"
    fi
}

db_action_one() {
    local action=$1
    local db_name=${2^^}
    local db_type_code

    db_type_code=$(db_type "$db_name") || {
        log "! Error: unable to determine database type for '$db_name'."
        return 1
    }

    if [[ $action == Start && ${db_type_code,,} == ora ]]; then
        oracle_listener "$db_name" start || {
            log "! Error: Oracle listener could not be started for SID '$db_name'."
            return 1
        }
    fi

    run_disruptive_command \
        "$SAPHOSTCTRL -function ${action}Database -dbname $db_name -dbtype $db_type_code" \
        "$SAPHOSTCTRL" \
        -function "${action}Database" \
        -dbname "$db_name" \
        -dbtype "$db_type_code"
}

db_action() {
    local action=$1
    local requested_db=${2^^}
    local db_name
    local status=0

    ((db_systems_found)) || {
        log "No database instances found."
        return 1
    }

    if [[ $requested_db == ALL ]]; then
        for db_name in "${db_systems_array[@]}"; do
            db_action_one "$action" "$db_name" || status=1
        done

        return "$status"
    fi

    db_action_one "$action" "$requested_db"
}

db_stop() {
    db_action Stop "$1"
}

db_start() {
    db_action Start "$1"
}

db_restart() {
    db_stop "$1" && db_start "$1"
}

get_instance_state() {
    local exit_code=$1
    local output=$2

    [[ $exit_code -eq 3 ]] && {
        printf 'RUNNING'
        return
    }

    [[ $exit_code -eq 4 ]] && {
        printf 'STOPPED'
        return
    }

    if [[ $output == *GREEN* &&
          $output != *RED* &&
          $output != *YELLOW* &&
          $output != *GRAY* &&
          $output != *GREY* ]]; then
        printf 'RUNNING'
    else
        printf 'PARTIALLY RUNNING'
    fi
}

instance_status_one() {
    local array_name=$1
    local index=$2
    local detailed=${3:-0}
    local -n records=$array_name
    local output
    local exit_code
    local state

    output=$(run_readonly_as_sidadm \
        "${records[index]}" \
        "sapcontrol -nr ${records[index + 3]} -function GetProcessList")
    exit_code=$?

    state=$(get_instance_state "$exit_code" "$output")

    log "$state - $(instance_label "$array_name" "$index")"

    if ((detailed)); then
        log "Instance Type: ${records[index + 2]} - $(instance_description "${records[index + 2]}")"
        printf '%s\n' "$output"
    fi

    [[ $state == RUNNING ]]
}

instance_status() {
    local requested_sid=${1^^}
    local detailed=${2:-0}
    local index
    local found=0
    local status=0
    local -n records=sap_instances_all_array

    ((sap_instances_found)) || {
        log "No SAP instances found."
        return 1
    }

    for ((index = 0; index < ${#records[@]}; index += 5)); do
        [[ -z $requested_sid ||
           $requested_sid == ALL ||
           $requested_sid == NONE ||
           ${records[index]} == "$requested_sid" ]] || continue

        found=1
        instance_status_one sap_instances_all_array "$index" "$detailed" || status=1

        ((detailed)) && log "===================================================="
    done

    ((found)) || {
        log "! Error: SID '$requested_sid' was not found."
        return 1
    }

    return "$status"
}

instance_list() {
    local requested_sid=${1^^}
    local index
    local -n records=sap_instances_all_array

    ((sap_instances_found)) || {
        log "No SAP instances found."
        return 1
    }

    for ((index = 0; index < ${#records[@]}; index += 5)); do
        [[ -z $requested_sid ||
           $requested_sid == ALL ||
           ${records[index]} == "$requested_sid" ]] &&
            log "$(instance_label sap_instances_all_array "$index")"
    done
}

instance_version() {
    local requested_sid=${1^^}
    local index
    local -n records=sap_instances_all_array

    ((sap_instances_found)) || return 1

    for ((index = 0; index < ${#records[@]}; index += 5)); do
        [[ -z $requested_sid ||
           $requested_sid == ALL ||
           ${records[index]} == "$requested_sid" ]] || continue

        log "$(instance_label sap_instances_all_array "$index")"

        run_readonly_as_sidadm \
            "${records[index]}" \
            "sapcontrol -nr ${records[index + 3]} -function GetVersionInfo"

        log "===================================================="
    done
}

wait_for_db_connectivity() {
    local sid=${1^^}
    local instance_label_text=$2
    local sid_lower=${sid,,}
    local r3trans_command="R3trans -d"
    local -i attempt
    local -i max_attempts=60
    local -i wait_seconds=10

    log "Checking database connectivity before starting ABAP instance: $instance_label_text"

    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        log "Attempt $attempt/$max_attempts: checking database connectivity using R3trans -d."
        log "Command: su - ${sid_lower}adm -c \"$r3trans_command\""

        if su - "${sid_lower}adm" -c "$r3trans_command" >/dev/null 2>&1; then
            log "SAP application user '${sid_lower}adm' can connect to the database."
            return 0
        fi

        if ((attempt < max_attempts)); then
            log "R3trans -d failed. Waiting $wait_seconds seconds before retrying."
            read -rt "$wait_seconds" _ || true
        fi
    done

    log "! Error: database connectivity was not established within 10 minutes."
    return 1
}

start_instance() {
    local array_name=$1
    local index=$2
    local -n records=$array_name

    local sid=${records[index]}
    local instance_type=${records[index + 2]}
    local instance_number=${records[index + 3]}
    local label

    label=$(instance_label "$array_name" "$index")

    case $instance_type in
        D|DVEBMGS)
            wait_for_db_connectivity "$sid" "$label" || {
                log "! Error: skipping startup of ABAP instance: $label"
                return 1
            }
            ;;
    esac

    log "Starting $(instance_description "$instance_type") ==> $label"

    run_disruptive_as_sidadm \
        "$sid" \
        "sapcontrol -nr $instance_number -function StartWait 300 10"
}

stop_instance() {
    local array_name=$1
    local index=$2
    local -n records=$array_name

    run_disruptive_as_sidadm \
        "${records[index]}" \
        "sapcontrol -nr ${records[index + 3]} -function StopWait 300 10"
}

process_instances() {
    local action=$1
    local array_name=$2
    local requested_sid=${3^^}
    local index
    local status=0
    local -n records=$array_name

    for ((index = 0; index < ${#records[@]}; index += 5)); do
        [[ $requested_sid == ALL || ${records[index]} == "$requested_sid" ]] || continue
        "${action}_instance" "$array_name" "$index" || status=1
    done

    return "$status"
}

system_status() {
    instance_status "$1"
}

system_stop() {
    local requested_sid=${1^^}
    local status=0

    process_instances stop sap_java_instances_array "$requested_sid" || status=1
    process_instances stop sap_abap_instances_array "$requested_sid" || status=1
    process_instances stop sap_scs_instances_array "$requested_sid" || status=1
    process_instances stop sap_ascs_instances_array "$requested_sid" || status=1
    process_instances stop sap_contentserver_instances_array "$requested_sid" || status=1
    process_instances stop sap_hdb_instances_array "$requested_sid" || status=1

    return "$status"
}

system_start() {
    local requested_sid=${1^^}
    local status=0

    process_instances start sap_hdb_instances_array "$requested_sid" || status=1
    process_instances start sap_ascs_instances_array "$requested_sid" || status=1
    process_instances start sap_scs_instances_array "$requested_sid" || status=1
    process_instances start sap_abap_instances_array "$requested_sid" || status=1
    process_instances start sap_java_instances_array "$requested_sid" || status=1
    process_instances start sap_contentserver_instances_array "$requested_sid" || status=1

    return "$status"
}

system_restart() {
    system_stop "$1" && system_start "$1"
}

all_stop() {
    local requested_sid=${1:-all}

    system_stop "$requested_sid" &&
        db_stop "$requested_sid"
}

all_start() {
    local requested_sid=${1:-all}

    db_start "$requested_sid" &&
        system_start "$requested_sid"
}

all_restart() {
    local requested_sid=${1:-all}

    all_stop "$requested_sid" &&
        all_start "$requested_sid"
}

all_status() {
    local requested_sid=${1:-all}
    local sid
    local status=0

    if [[ -z $requested_sid || ${requested_sid,,} == all ]]; then
        for sid in "${sap_systems_array[@]}"; do
            log "=== Checking status for SAP system: $sid"

            instance_status "$sid" || status=1
            db_status_for_sid "$sid" || status=1

            log "===================================================="
        done

        return "$status"
    fi

    log "=== Checking status for SAP system: ${requested_sid^^}"

    instance_status "$requested_sid" || status=1
    db_status_for_sid "$requested_sid" || status=1

    return "$status"
}

display_help() {
    printf '%s\n' \
        "Usage: $0 <command> [option]" \
        "" \
        "Commands:" \
        "  instance_list [SID|all]" \
        "  instance_status [SID|all]" \
        "  instance_status_det [SID|all]" \
        "  instance_version [SID|all]" \
        "  system_status [SID|all]" \
        "  system_stop <SID|all>" \
        "  system_start <SID|all>" \
        "  system_restart <SID|all>" \
        "  db_list" \
        "  db_status [DBNAME|all]" \
        "  db_status_det [DBNAME|all]" \
        "  db_stop <DBNAME|all>" \
        "  db_start <DBNAME|all>" \
        "  db_restart <DBNAME|all>" \
        "  db_type <DBNAME>" \
        "  all_stop [SID|all]" \
        "  all_start [SID|all]" \
        "  all_restart [SID|all]" \
        "  all_status [SID|all]"
}

if (($# == 0)) || [[ $1 == help ]]; then
    display_help
    exit 0
fi

command=$1
option=${2:-}

case $command in
    instance_list|instance_status|instance_status_det|instance_version|system_status|db_status|db_status_det|db_type|all_status|all_stop|all_start|all_restart)
        (($# <= 2)) || {
            log "! Error: too many arguments for '$command'."
            display_help
            exit 1
        }
        ;;
    system_stop|system_start|system_restart|db_stop|db_start|db_restart)
        (($# == 2)) && [[ -n $option ]] || {
            log "! Error: command '$command' requires an SID, database name, or 'all'."
            display_help
            exit 1
        }
        ;;
    db_list)
        (($# == 1)) || {
            log "! Error: command '$command' does not accept arguments."
            display_help
            exit 1
        }
        ;;
    *)
        log "! Error: unknown command '$command'."
        display_help
        exit 1
        ;;
esac

if ((testexec)); then
    log "TEST MODE: Read-only commands execute; disruptive commands are simulated."
else
    log "EXECUTION MODE: All commands execute."
fi

log "Script called with command '$command' and option '$option'."

case $command in
    instance_list)
        find_sap_instances
        instance_list "$option"
        ;;
    instance_status)
        find_sap_instances
        instance_status "$option"
        ;;
    instance_status_det)
        find_sap_instances
        instance_status "$option" 1
        ;;
    instance_version)
        find_sap_instances
        instance_version "$option"
        ;;
    system_status)
        find_sap_instances
        system_status "$option"
        ;;
    system_stop)
        find_sap_instances
        system_stop "$option"
        ;;
    system_start)
        find_sap_instances
        system_start "$option"
        ;;
    system_restart)
        find_sap_instances
        system_restart "$option"
        ;;
    db_list)
        find_db_systems
        db_list
        ;;
    db_status)
        find_db_systems
        db_status "$option"
        ;;
    db_status_det)
        find_db_systems
        db_status_det "$option"
        ;;
    db_stop)
        find_db_systems
        db_stop "$option"
        ;;
    db_start)
        find_db_systems
        db_start "$option"
        ;;
    db_restart)
        find_db_systems
        db_restart "$option"
        ;;
    db_type)
        [[ -n $option ]] || {
            log "! Error: command 'db_type' requires a database name."
            exit 1
        }

        find_db_systems
        db_type "$option"
        ;;
    all_stop)
        find_sap_instances
        find_db_systems
        all_stop "$option"
        ;;
    all_start)
        find_sap_instances
        find_db_systems
        all_start "$option"
        ;;
    all_restart)
        find_sap_instances
        find_db_systems
        all_restart "$option"
        ;;
    all_status)
        find_sap_instances
        find_db_systems
        all_status "$option"
        ;;
esac
