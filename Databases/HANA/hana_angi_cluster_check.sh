#!/usr/bin/env bash
#
# hana_angi_cluster_preflight.sh
#
# Read-only validation for an active/passive SAP HANA System Replication
# cluster on SLES for SAP Applications using:
#   - SAPHanaSR-angi
#   - Pacemaker / Corosync
#   - Azure Fence Agent
#   - Azure Load Balancer
#
# Run as root on each HANA cluster node:
#   ./hana_angi_cluster_preflight.sh
#
# Optional overrides:
#   ./hana_angi_cluster_preflight.sh --sid PPR --instance 00 --sites SITE1,SITE2
#
# The script does not change HANA, Pacemaker, Azure, fencing, or networking.

set -uo pipefail

SID=""
INSTANCE=""
SITES=""
GLOBAL_INI=""
FAILURES=0
WARNINGS=0

usage() {
    cat <<'EOF'
Usage:
  hana_angi_cluster_preflight.sh [options]

Default behavior:
  - Detects HANA SID and instance number from /usr/sap/<SID>/HDB<NN>.
  - Detects HANA SR sites from /etc/sudoers.d/20-saphana.

Options:
  --sid <SID>              Override detected SID.
  --instance <NN>          Override detected instance number.
  --sites <SITE1,SITE2>    Override detected HANA SR sites.
  --global-ini <path>      Override default global.ini location.
  -h, --help               Display this help text.

EOF
}

pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
info() { printf 'INFO  %s\n' "$*"; }

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

rpm_installed() {
    rpm -q "$1" >/dev/null 2>&1
}

require_command() {
    if command_exists "$1"; then
        pass "Command available: $1"
    else
        fail "Required command is missing: $1"
    fi
}

check_service_active() {
    local service="$1"

    if systemctl is-active --quiet "$service"; then
        pass "Service is active: ${service}"
    else
        fail "Service is not active: ${service}"
    fi
}

# crm configure get_property returns the value directly.
get_cluster_property() {
    local property="$1"
    local value

    value="$(crm configure get_property "$property" 2>/dev/null)" || return 1
    printf '%s\n' "$value"
}

check_resource_agent() {
    local agent="$1"

    if crm ra meta "$agent" >/dev/null 2>&1; then
        pass "Resource agent is available: ${agent}"
    else
        fail "Resource agent is unavailable: ${agent}"
    fi
}

# SLES for SAP is identified through SUSE product metadata.
is_sles_for_sap() {
    local product_file

    for product_file in /etc/products.d/baseproduct /etc/products.d/*.prod; do
        [[ -r "$product_file" ]] || continue

        if grep -qiE 'SLES_SAP|SUSE Linux Enterprise Server for SAP Applications' \
            "$product_file"; then
            return 0
        fi
    done

    return 1
}

# Detect /usr/sap/<SID>/HDB<NN>. Supports directories and symbolic links.
detect_hana_installation() {
    local path detected_sid detected_instance
    local -a installations=()

    for path in /usr/sap/*/HDB[0-9][0-9]; do
        [[ -e "$path" || -L "$path" ]] || continue

        detected_sid="$(basename "$(dirname "$path")")"
        detected_instance="${path##*/HDB}"

        if [[ "$detected_sid" =~ ^[A-Za-z0-9]{3}$ ]] &&
           [[ "$detected_instance" =~ ^[0-9]{2}$ ]]; then
            installations+=("${detected_sid^^}:${detected_instance}")
        fi
    done

    if [[ ${#installations[@]} -gt 0 ]]; then
        mapfile -t installations < <(
            printf '%s\n' "${installations[@]}" | sort -u
        )
    fi

    if [[ ${#installations[@]} -eq 0 ]]; then
        fail "Could not auto-detect a HANA installation below /usr/sap"
        info "Expected a path such as /usr/sap/<SID>/HDB<NN>"
        info "Run: ls -ld /usr/sap/*/HDB*"
        return 1
    fi

    if [[ ${#installations[@]} -gt 1 ]]; then
        fail "More than one HANA installation was detected: ${installations[*]}"
        info "Use --sid and --instance to select the intended HANA database"
        return 1
    fi

    IFS=':' read -r SID INSTANCE <<< "${installations[0]}"
    pass "Auto-detected HANA installation: SID=${SID}, instance=HDB${INSTANCE}"
    return 0
}

# Detect HANA SR site names from SAPHanaSR-angi sudoers hook attributes.
detect_hsr_sites() {
    local sudoers_file="/etc/sudoers.d/20-saphana"
    local site_prefix
    local -a detected_sites=()

    if [[ ! -r "$sudoers_file" ]]; then
        fail "Cannot auto-detect HSR sites because ${sudoers_file} is missing or unreadable"
        return 1
    fi

    site_prefix="hana_${SID_LOWER}_site_srHook_"

    mapfile -t detected_sites < <(
        grep -Eo "${site_prefix}[A-Za-z0-9_.-]+" "$sudoers_file" \
            | sed "s/^${site_prefix}//" \
            | sort -u
    )

    if [[ ${#detected_sites[@]} -ne 2 ]]; then
        fail "Expected exactly two HSR sites, but detected: ${detected_sites[*]:-none}"
        info "Use --sites SITE1,SITE2 if the sudoers file uses a non-standard format"
        return 1
    fi

    SITES="${detected_sites[0]},${detected_sites[1]}"
    pass "Auto-detected HSR sites: ${SITES}"
    return 0
}

# Extract a complete CRM object, including continuation lines, from the
# output stored in /tmp/crm_config.$$.
crm_object_block() {
    local object_id="$1"

    awk -v object_id="$object_id" '
        $1 ~ /^(primitive|clone|group|colocation|order|location|property|rsc_defaults|op_defaults)$/ {
            if (in_block) {
                exit
            }

            if ($2 == object_id) {
                in_block = 1
            }
        }

        in_block {
            print
        }
    ' /tmp/crm_config.$$
}

# Extract node names from crm_mon output.
# Supports both:
#   * Promoted: [ node ]
#   * Masters:  [ node ]

# Extract node names from crm_mon output.
# Supports both:
#   * Promoted: [ node ]
#   * Masters:  [ node ]
#
# The result is trimmed so comparisons against resource hosting nodes work.
get_crm_role_nodes() {
    local first_label="$1"
    local second_label="$2"
    local crm_mon_file="$3"

    awk -v first_label="$first_label" -v second_label="$second_label" '
        $0 ~ "(" first_label "|" second_label "):[[:space:]]*\\[" {
            line = $0

            # Keep only the text inside the square brackets.
            sub(/^.*\[/, "", line)
            sub(/\].*$/, "", line)

            # Remove leading and trailing whitespace before returning the node.
            gsub(/^[[:space:]]+/, "", line)
            gsub(/[[:space:]]+$/, "", line)

            print line
            exit
        }
    ' "$crm_mon_file"
}


while [[ $# -gt 0 ]]; do
    case "$1" in
        --sid)
            SID="${2:-}"
            shift 2
            ;;
        --instance)
            INSTANCE="${2:-}"
            shift 2
            ;;
        --sites)
            SITES="${2:-}"
            shift 2
            ;;
        --global-ini)
            GLOBAL_INI="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n\n' "$1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    printf 'This script must be run as root.\n' >&2
    exit 2
fi

if [[ -z "$SID" && -z "$INSTANCE" ]]; then
    detect_hana_installation || exit 2
elif [[ -z "$SID" || -z "$INSTANCE" ]]; then
    printf 'Specify both --sid and --instance, or omit both for auto-detection.\n' >&2
    exit 2
fi

if ! [[ "$SID" =~ ^[A-Za-z0-9]{3}$ ]]; then
    printf 'SID must be a three-character SAP system ID.\n' >&2
    exit 2
fi

if ! [[ "$INSTANCE" =~ ^[0-9]{2}$ ]]; then
    printf 'Instance number must contain two digits, for example: 00 or 03.\n' >&2
    exit 2
fi

SID="${SID^^}"
SID_LOWER="${SID,,}"

if [[ -z "$SITES" ]]; then
    detect_hsr_sites || exit 2
fi

IFS=',' read -r -a SITE_ARRAY <<< "$SITES"

if [[ ${#SITE_ARRAY[@]} -ne 2 ]] ||
   [[ -z "${SITE_ARRAY[0]}" ]] ||
   [[ -z "${SITE_ARRAY[1]}" ]]; then
    printf 'Exactly two HSR sites are required, for example: SITE1,SITE2.\n' >&2
    exit 2
fi

if [[ -z "$GLOBAL_INI" ]]; then
    GLOBAL_INI="/hana/shared/${SID}/global/hdb/custom/config/global.ini"
fi

HOST="$(hostname -s)"

printf '\n============================================================\n'
printf 'HANA SAPHanaSR-angi cluster preflight\n'
printf 'Host: %s | SID: %s | Instance: HDB%s | Sites: %s\n' \
    "$HOST" "$SID" "$INSTANCE" "$SITES"
printf '============================================================\n'

info "This script is read-only. It does not alter CRM, HANA, Azure, or fencing configuration."

# ===========================================================================
# Operating system and base command checks
# ===========================================================================
printf '\n--- Operating system and base commands ---\n'

require_command rpm
require_command systemctl
require_command crm
require_command crm_mon
require_command crm_node
require_command crm_resource
require_command cibadmin
require_command visudo
require_command findmnt
require_command getent
require_command awk
require_command grep
require_command sed

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    pass "Operating system detected: ${PRETTY_NAME:-unknown}"

    if awk "BEGIN {exit !(${VERSION_ID:-0} >= 15.4)}" 2>/dev/null; then
        pass "SLES version meets SAPHanaSR-angi minimum requirement of SLES 15 SP4"
    else
        fail "SAPHanaSR-angi requires at least SLES for SAP Applications 15 SP4"
    fi
else
    fail "Cannot read /etc/os-release"
fi

if is_sles_for_sap; then
    pass "SLES for SAP Applications product detected in /etc/products.d"
else
    fail "SLES for SAP Applications was not detected in /etc/products.d"
fi

# ===========================================================================
# SAPHanaSR-angi, HANA, Pacemaker, and Corosync
# ===========================================================================
printf '\n--- SAPHanaSR-angi and base cluster prerequisites ---\n'

if rpm_installed "SAPHanaSR-angi"; then
    pass "SAPHanaSR-angi package installed: $(rpm -q SAPHanaSR-angi)"
else
    fail "SAPHanaSR-angi is not installed"
fi

if rpm_installed "SAPHanaSR"; then
    fail "Classic SAPHanaSR is installed. SAPHanaSR and SAPHanaSR-angi are mutually exclusive."
else
    pass "Classic SAPHanaSR package is not installed"
fi

check_resource_agent "ocf:suse:SAPHanaTopology"
check_resource_agent "ocf:suse:SAPHanaController"
check_resource_agent "ocf:heartbeat:IPaddr2"
check_resource_agent "ocf:heartbeat:azure-lb"

if id "${SID_LOWER}adm" >/dev/null 2>&1; then
    pass "HANA operating-system user exists: ${SID_LOWER}adm"

    if su - "${SID_LOWER}adm" -c "HDB version" >/tmp/hana_version.$$ 2>&1; then
        pass "HANA command environment is operational for ${SID_LOWER}adm"
        sed 's/^/INFO  HANA: /' /tmp/hana_version.$$ | head -n 4
    else
        warn "Unable to execute 'HDB version' as ${SID_LOWER}adm"
    fi

    rm -f /tmp/hana_version.$$
else
    fail "HANA operating-system user does not exist: ${SID_LOWER}adm"
fi

check_service_active corosync
check_service_active pacemaker

if crm_mon -1 >/tmp/crm_mon.$$ 2>&1; then
    pass "Pacemaker cluster is queryable"
    grep -E 'Online:|OFFLINE:|RemoteOnline:' /tmp/crm_mon.$$ | sed 's/^/INFO  /'
else
    fail "crm_mon could not query the cluster"
fi

rm -f /tmp/crm_mon.$$

STONITH_ENABLED="$(get_cluster_property stonith-enabled || true)"
if [[ "$STONITH_ENABLED" == "true" ]]; then
    pass "Cluster property stonith-enabled=true"
else
    fail "Cluster property stonith-enabled must be true; current value: '${STONITH_ENABLED:-unset}'"
fi

NO_QUORUM_POLICY="$(get_cluster_property no-quorum-policy || true)"
if [[ -n "$NO_QUORUM_POLICY" ]]; then
    info "Cluster property no-quorum-policy=${NO_QUORUM_POLICY}"
else
    warn "Cluster property no-quorum-policy is not explicitly configured"
fi

PRIORITY_FENCING_DELAY="$(get_cluster_property priority-fencing-delay || true)"
if [[ -n "$PRIORITY_FENCING_DELAY" ]]; then
    pass "Cluster property priority-fencing-delay=${PRIORITY_FENCING_DELAY}"
else
    warn "priority-fencing-delay is not configured"
fi

if cibadmin -Q >/tmp/cib.$$ 2>/dev/null; then
    pass "Cluster Information Base (CIB) is readable"
else
    fail "Unable to read the Cluster Information Base"
    : >/tmp/cib.$$
fi

# ===========================================================================
# Azure fencing and networking
# ===========================================================================
printf '\n--- Azure fencing and networking ---\n'

if crm ra meta "stonith:fence_azure_arm" >/dev/null 2>&1 ||
   command_exists fence_azure_arm; then
    pass "Azure Fence Agent is installed and available"
else
    fail "Azure Fence Agent is unavailable"
fi

mapfile -t AZURE_FENCE_RESOURCES < <(
    crm configure show 2>/dev/null \
        | awk '$1 == "primitive" && $0 ~ /fence_azure_arm/ {print $2}'
)

if [[ ${#AZURE_FENCE_RESOURCES[@]} -eq 0 ]]; then
    fail "No Pacemaker STONITH resource using fence_azure_arm is configured"
else
    for fence_resource in "${AZURE_FENCE_RESOURCES[@]}"; do
        pass "Azure fencing resource configured: ${fence_resource}"

        host_map="$(
            crm_resource --resource "$fence_resource" \
                --get-parameter pcmk_host_map 2>/dev/null || true
        )"

        if [[ -n "$host_map" && "$host_map" != "default" ]]; then
            pass "Azure fence resource ${fence_resource} has pcmk_host_map configured"
        else
            warn "Azure fence resource ${fence_resource} has no explicit pcmk_host_map"
        fi

        fence_delay="$(
            crm_resource --resource "$fence_resource" \
                --get-parameter pcmk_delay_max 2>/dev/null || true
        )"

        if [[ -n "$fence_delay" && "$fence_delay" != "default" ]]; then
            pass "Azure fence resource ${fence_resource} has pcmk_delay_max=${fence_delay}"
        else
            warn "pcmk_delay_max is not explicitly configured on ${fence_resource}"
        fi
    done
fi

if grep -qiE 'fence[_-]netapp|netapp' /tmp/cib.$$; then
    fail "A NetApp-related fencing configuration was found in the CIB"
else
    pass "No NetApp fencing configuration found in the CIB"
fi

TCP_TIMESTAMPS="$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null || true)"

if [[ "$TCP_TIMESTAMPS" == "0" ]]; then
    pass "net.ipv4.tcp_timestamps=0"
else
    fail "net.ipv4.tcp_timestamps must be 0 for Azure Load Balancer health probes"
fi

while read -r cluster_node; do
    [[ -z "$cluster_node" ]] && continue

    if getent hosts "$cluster_node" >/dev/null 2>&1; then
        pass "Hostname resolution works for cluster node: ${cluster_node}"
    else
        fail "Hostname resolution failed for cluster node: ${cluster_node}"
    fi
done < <(crm_node -l 2>/dev/null | awk '{print $2}')

# ===========================================================================
# HANA storage, replication, HA/DR hooks, and sudoers
# ===========================================================================
printf '\n--- HANA storage, replication, and HA/DR hooks ---\n'

for hana_mount in "/hana/data/${SID}" "/hana/log/${SID}" "/hana/shared/${SID}"; do
    if findmnt -T "$hana_mount" >/dev/null 2>&1; then
        mount_type="$(findmnt -n -o FSTYPE -T "$hana_mount" 2>/dev/null)"
        mount_source="$(findmnt -n -o SOURCE -T "$hana_mount" 2>/dev/null)"
        pass "Mount available: ${hana_mount} (${mount_type}, ${mount_source})"

        if [[ "$mount_type" =~ ^nfs ]]; then
            warn "${hana_mount} uses ${mount_type}; validate the intended shared-storage architecture"
        fi
    else
        fail "Required HANA mount is unavailable: ${hana_mount}"
    fi
done

if su - "${SID_LOWER}adm" -c "hdbnsutil -sr_state" >/tmp/sr_state.$$ 2>&1; then
    pass "HANA System Replication state is queryable"
    sed 's/^/INFO  SR: /' /tmp/sr_state.$$ | head -n 40

    if grep -qiE 'primary|secondary' /tmp/sr_state.$$; then
        pass "HANA System Replication roles are present"
    else
        fail "HANA System Replication output does not show a primary or secondary role"
    fi
else
    fail "Unable to query HANA System Replication with hdbnsutil -sr_state"
fi

rm -f /tmp/sr_state.$$

if [[ -r "$GLOBAL_INI" ]]; then
    pass "HANA global.ini found: ${GLOBAL_INI}"

    if grep -qE '^[[:space:]]*provider[[:space:]]*=[[:space:]]*susHanaSR[[:space:]]*$' "$GLOBAL_INI"; then
        pass "susHanaSR HA/DR provider is configured"
    else
        fail "susHanaSR HA/DR provider is not configured"
    fi

    if grep -qE '^[[:space:]]*provider[[:space:]]*=[[:space:]]*susChkSrv[[:space:]]*$' "$GLOBAL_INI"; then
        pass "susChkSrv HA/DR provider is configured"

        if grep -qE '^[[:space:]]*action_on_lost[[:space:]]*=[[:space:]]*fence[[:space:]]*$' "$GLOBAL_INI"; then
            pass "susChkSrv action_on_lost=fence is configured"
        else
            warn "susChkSrv is configured but action_on_lost=fence was not found"
        fi
    else
        warn "susChkSrv HA/DR provider is not configured"
    fi
else
    fail "Cannot read HANA global.ini: ${GLOBAL_INI}"
fi

SUDOERS_FILE="/etc/sudoers.d/20-saphana"

if [[ -r "$SUDOERS_FILE" ]]; then
    if visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
        pass "SAPHanaSR-angi sudoers file has valid syntax"
    else
        fail "Invalid sudoers syntax: ${SUDOERS_FILE}"
    fi

    if grep -q "${SID_LOWER}adm" "$SUDOERS_FILE"; then
        pass "sudoers file contains permissions for ${SID_LOWER}adm"
    else
        fail "sudoers file does not contain permissions for ${SID_LOWER}adm"
    fi

    for site in "${SITE_ARRAY[@]}"; do
        if grep -q "hana_${SID_LOWER}_site_srHook_${site}" "$SUDOERS_FILE"; then
            pass "sudoers permissions found for HANA site hook: ${site}"
        else
            fail "Missing sudoers permissions for HANA site hook: ${site}"
        fi
    done

    if grep -q "SAPHanaSR-hookHelper.*--sid=${SID}" "$SUDOERS_FILE"; then
        pass "sudoers contains SAPHanaSR-hookHelper permissions for SID ${SID}"
    else
        fail "sudoers is missing SAPHanaSR-hookHelper permissions for SID ${SID}"
    fi
else
    fail "Required SAPHanaSR-angi sudoers file is missing: ${SUDOERS_FILE}"
fi

# ===========================================================================
# Active/passive SAPHanaSR-angi resource configuration
# ===========================================================================
printf '\n--- Validate implemented HANA cluster resources (active/passive) ---\n'

RSC_TOPOLOGY="rsc_SAPHanaTopology_${SID}_HDB${INSTANCE}"
CLN_TOPOLOGY="cln_SAPHanaTopology_${SID}_HDB${INSTANCE}"

RSC_CONTROLLER="rsc_SAPHanaController_${SID}_HDB${INSTANCE}"
MSL_CONTROLLER="msl_SAPHanaController_${SID}_HDB${INSTANCE}"

RSC_IP="rsc_ip_${SID}_HDB${INSTANCE}"
RSC_AZURE_LB="rsc_nc_${SID}_HDB${INSTANCE}"
GRP_IP="g_ip_${SID}_HDB${INSTANCE}"

COL_IP="col_saphana_ip_${SID}_HDB${INSTANCE}"
ORD_HANA="ord_SAPHana_${SID}_HDB${INSTANCE}"

RSC_SECONDARY_IP="rsc_secip_${SID}_HDB${INSTANCE}"
RSC_SECONDARY_AZURE_LB="rsc_secnc_${SID}_HDB${INSTANCE}"
GRP_SECONDARY_IP="g_secip_${SID}_HDB${INSTANCE}"

if crm configure show >/tmp/crm_config.$$ 2>/dev/null; then
    pass "Pacemaker configuration is queryable"
else
    fail "Unable to read Pacemaker configuration with 'crm configure show'"
    : >/tmp/crm_config.$$
fi

TOPOLOGY_CFG="$(crm_object_block "$RSC_TOPOLOGY")"
TOPOLOGY_CLONE_CFG="$(crm_object_block "$CLN_TOPOLOGY")"

CONTROLLER_CFG="$(crm_object_block "$RSC_CONTROLLER")"
CONTROLLER_CLONE_CFG="$(crm_object_block "$MSL_CONTROLLER")"

IP_CFG="$(crm_object_block "$RSC_IP")"
AZURE_LB_CFG="$(crm_object_block "$RSC_AZURE_LB")"
IP_GROUP_CFG="$(crm_object_block "$GRP_IP")"

IP_COLOCATION_CFG="$(crm_object_block "$COL_IP")"
HANA_ORDER_CFG="$(crm_object_block "$ORD_HANA")"

if grep -qE "^primitive[[:space:]]+${RSC_TOPOLOGY}[[:space:]]+(ocf:suse:)?SAPHanaTopology([[:space:]]|$)" <<< "$TOPOLOGY_CFG"; then
    pass "SAPHanaTopology primitive is configured: ${RSC_TOPOLOGY}"
else
    fail "Missing or invalid SAPHanaTopology primitive: ${RSC_TOPOLOGY}"
fi

if grep -qE '(^|[[:space:]])SID="?'"${SID}"'?([[:space:]]|$)' <<< "$TOPOLOGY_CFG" &&
   grep -qE '(^|[[:space:]])InstanceNumber="?'"${INSTANCE}"'?([[:space:]]|$)' <<< "$TOPOLOGY_CFG"; then
    pass "SAPHanaTopology SID and instance parameters are correct"
else
    fail "SAPHanaTopology SID=${SID} and/or InstanceNumber=${INSTANCE} parameters were not found"
fi

if grep -qE "^clone[[:space:]]+${CLN_TOPOLOGY}[[:space:]]+${RSC_TOPOLOGY}([[:space:]]|$)" <<< "$TOPOLOGY_CLONE_CFG"; then
    pass "SAPHanaTopology clone is configured: ${CLN_TOPOLOGY}"
else
    fail "Missing or invalid SAPHanaTopology clone: ${CLN_TOPOLOGY}"
fi

if grep -qE '(^|[[:space:]])clone-node-max="?1"?([[:space:]]|$)' <<< "$TOPOLOGY_CLONE_CFG"; then
    pass "SAPHanaTopology clone-node-max is set to 1"
else
    warn "Could not confirm clone-node-max=1 for ${CLN_TOPOLOGY}"
fi

if grep -qE '(^|[[:space:]])interleave="?true"?([[:space:]]|$)' <<< "$TOPOLOGY_CLONE_CFG"; then
    pass "SAPHanaTopology clone interleave is enabled"
else
    warn "Could not confirm interleave=true for ${CLN_TOPOLOGY}"
fi

if grep -qE "^primitive[[:space:]]+${RSC_CONTROLLER}[[:space:]]+(ocf:suse:)?SAPHanaController([[:space:]]|$)" <<< "$CONTROLLER_CFG"; then
    pass "SAPHanaController primitive is configured: ${RSC_CONTROLLER}"
else
    fail "Missing or invalid SAPHanaController primitive: ${RSC_CONTROLLER}"
fi

if grep -qE "^clone[[:space:]]+${MSL_CONTROLLER}[[:space:]]+${RSC_CONTROLLER}([[:space:]]|$)" <<< "$CONTROLLER_CLONE_CFG"; then
    pass "SAPHanaController clone is configured: ${MSL_CONTROLLER}"
else
    fail "Missing or invalid SAPHanaController clone: ${MSL_CONTROLLER}"
fi

if grep -qE '(^|[[:space:]])promotable="?true"?([[:space:]]|$)' <<< "$CONTROLLER_CLONE_CFG"; then
    pass "SAPHanaController clone is configured as promotable"
else
    fail "SAPHanaController clone is not configured as promotable"
fi

if grep -qE '(^|[[:space:]])clone-node-max="?1"?([[:space:]]|$)' <<< "$CONTROLLER_CLONE_CFG"; then
    pass "SAPHanaController clone-node-max is set to 1"
else
    warn "Could not confirm clone-node-max=1 for ${MSL_CONTROLLER}"
fi

if grep -qE '(^|[[:space:]])interleave="?true"?([[:space:]]|$)' <<< "$CONTROLLER_CLONE_CFG"; then
    pass "SAPHanaController clone interleave is enabled"
else
    warn "Could not confirm interleave=true for ${MSL_CONTROLLER}"
fi

if grep -qE '(^|[[:space:]])PREFER_SITE_TAKEOVER="?(true|false)"?([[:space:]]|$)' <<< "$CONTROLLER_CFG"; then
    pass "SAPHanaController PREFER_SITE_TAKEOVER parameter is configured"
else
    warn "SAPHanaController PREFER_SITE_TAKEOVER parameter was not found"
fi

if grep -qE '(^|[[:space:]])DUPLICATE_PRIMARY_TIMEOUT="?[0-9]+"?([[:space:]]|$)' <<< "$CONTROLLER_CFG"; then
    pass "SAPHanaController DUPLICATE_PRIMARY_TIMEOUT parameter is configured"
else
    warn "SAPHanaController DUPLICATE_PRIMARY_TIMEOUT parameter was not found"
fi

if grep -qE '(^|[[:space:]])AUTOMATED_REGISTER="?(true|false)"?([[:space:]]|$)' <<< "$CONTROLLER_CFG"; then
    pass "SAPHanaController AUTOMATED_REGISTER parameter is configured"

    if grep -qE '(^|[[:space:]])AUTOMATED_REGISTER="?false"?([[:space:]]|$)' <<< "$CONTROLLER_CFG"; then
        warn "AUTOMATED_REGISTER=false is configured. Set it to true after failover testing is complete."
    fi
else
    warn "SAPHanaController AUTOMATED_REGISTER parameter was not found"
fi

if grep -qE "^primitive[[:space:]]+${RSC_IP}[[:space:]]+(ocf:heartbeat:)?IPaddr2([[:space:]]|$)" <<< "$IP_CFG"; then
    pass "Primary virtual IP resource is configured: ${RSC_IP}"
else
    fail "Missing or invalid primary virtual IP resource: ${RSC_IP}"
fi

if grep -qE "^primitive[[:space:]]+${RSC_AZURE_LB}[[:space:]]+azure-lb([[:space:]]|$)" <<< "$AZURE_LB_CFG"; then
    pass "Azure Load Balancer probe resource is configured: ${RSC_AZURE_LB}"
else
    fail "Missing or invalid Azure Load Balancer probe resource: ${RSC_AZURE_LB}"
fi

EXPECTED_PROBE_PORT="625${INSTANCE}"

if grep -qE '(^|[[:space:]])port='"${EXPECTED_PROBE_PORT}"'([[:space:]]|$)' <<< "$AZURE_LB_CFG"; then
    pass "Azure Load Balancer probe uses expected port: ${EXPECTED_PROBE_PORT}"
else
    fail "Azure Load Balancer probe port ${EXPECTED_PROBE_PORT} was not found for ${RSC_AZURE_LB}"
fi

if grep -qE "^group[[:space:]]+${GRP_IP}([[:space:]]|$)" <<< "$IP_GROUP_CFG" &&
   grep -qF "$RSC_IP" <<< "$IP_GROUP_CFG" &&
   grep -qF "$RSC_AZURE_LB" <<< "$IP_GROUP_CFG"; then
    pass "Primary virtual IP and Azure Load Balancer probe are grouped: ${GRP_IP}"
else
    fail "Missing or invalid primary IP group: ${GRP_IP}"
fi

if grep -qF "${GRP_IP}:Started" <<< "$IP_COLOCATION_CFG" &&
   grep -qE "${MSL_CONTROLLER}:(Promoted|Master)" <<< "$IP_COLOCATION_CFG"; then
    pass "Primary IP group is colocated with the primary HANA controller"
else
    fail "Missing expected colocation between ${GRP_IP} and ${MSL_CONTROLLER}"
fi

if [[ -n "$HANA_ORDER_CFG" ]] &&
   grep -qF "$CLN_TOPOLOGY" <<< "$HANA_ORDER_CFG" &&
   grep -qF "$MSL_CONTROLLER" <<< "$HANA_ORDER_CFG"; then
    pass "Topology-to-controller ordering constraint is configured"
else
    warn "Topology-to-controller ordering constraint ${ORD_HANA} was not found"
fi

if grep -qE "${RSC_SECONDARY_IP}|${RSC_SECONDARY_AZURE_LB}|${GRP_SECONDARY_IP}" /tmp/crm_config.$$; then
    fail "Secondary read-enabled IP resources were found. This is not an active/passive-only configuration."
else
    pass "No secondary read-enabled IP resources were found"
fi

# ===========================================================================
# Active/passive runtime validation
# ===========================================================================
printf '\n--- Validate active/passive runtime state ---\n'

# -1 is mandatory to prevent crm_mon from running continuously.
if crm_mon -1 -r >/tmp/crm_mon_resources.$$ 2>&1; then
    pass "Pacemaker runtime resource status is queryable"
else
    fail "Unable to read runtime resource status with 'crm_mon -1 -r'"
    : >/tmp/crm_mon_resources.$$
fi

if grep -q "Failed Resource Actions:" /tmp/crm_mon_resources.$$ ||
   grep -q "Failed Actions:" /tmp/crm_mon_resources.$$; then
    fail "Pacemaker reports failed resource actions"
else
    pass "Pacemaker reports no failed resource actions"
fi

# Supports both modern Promoted/Unpromoted and legacy Masters/Slaves output.
PRIMARY_NODES="$(
    get_crm_role_nodes "Promoted" "Masters" /tmp/crm_mon_resources.$$
)"

SECONDARY_NODES="$(
    get_crm_role_nodes "Unpromoted" "Slaves" /tmp/crm_mon_resources.$$
)"

PRIMARY_COUNT="$(wc -w <<< "$PRIMARY_NODES")"
SECONDARY_COUNT="$(wc -w <<< "$SECONDARY_NODES")"

if [[ "$PRIMARY_COUNT" -eq 1 ]]; then
    pass "Exactly one SAPHanaController instance has the primary role: ${PRIMARY_NODES}"
else
    fail "Expected exactly one primary SAPHanaController instance; found: '${PRIMARY_NODES:-none}'"
fi

if [[ "$SECONDARY_COUNT" -eq 1 ]]; then
    pass "Exactly one SAPHanaController instance has the secondary role: ${SECONDARY_NODES}"
else
    fail "Expected exactly one secondary SAPHanaController instance; found: '${SECONDARY_NODES:-none}'"
fi

# Resource lines may have a leading Pacemaker "*" marker. Search for the
# resource name anywhere in a line that also reports Started.
VIP_NODE="$(
    awk -v resource="$RSC_IP" '
        index($0, resource) && $0 ~ /Started/ {
            print $NF
            exit
        }
    ' /tmp/crm_mon_resources.$$
)"

AZURE_LB_NODE="$(
    awk -v resource="$RSC_AZURE_LB" '
        index($0, resource) && $0 ~ /Started/ {
            print $NF
            exit
        }
    ' /tmp/crm_mon_resources.$$
)"

if [[ -n "$VIP_NODE" ]]; then
    pass "Primary virtual IP resource is running on: ${VIP_NODE}"
else
    fail "Primary virtual IP resource ${RSC_IP} is not reported as Started"
fi

if [[ -n "$AZURE_LB_NODE" ]]; then
    pass "Azure Load Balancer probe resource is running on: ${AZURE_LB_NODE}"
else
    fail "Azure Load Balancer probe resource ${RSC_AZURE_LB} is not reported as Started"
fi

if [[ -n "$PRIMARY_NODES" && "$VIP_NODE" == "$PRIMARY_NODES" ]]; then
    pass "Primary virtual IP is aligned with the primary HANA controller"
else
    fail "Primary virtual IP node '${VIP_NODE:-none}' does not match the primary HANA controller node '${PRIMARY_NODES:-none}'"
fi

if [[ -n "$PRIMARY_NODES" && "$AZURE_LB_NODE" == "$PRIMARY_NODES" ]]; then
    pass "Azure Load Balancer probe is aligned with the primary HANA controller"
else
    fail "Azure Load Balancer probe node '${AZURE_LB_NODE:-none}' does not match the primary HANA controller node '${PRIMARY_NODES:-none}'"
fi

if command_exists SAPHanaSR-showAttr; then
    if SAPHanaSR-showAttr >/tmp/saphanasr_showattr.$$ 2>&1; then
        pass "SAPHanaSR-showAttr completed successfully"
        sed 's/^/INFO  SAPHanaSR: /' /tmp/saphanasr_showattr.$$ | head -n 80
    else
        warn "SAPHanaSR-showAttr could not retrieve HANA SR cluster attributes"
    fi

    rm -f /tmp/saphanasr_showattr.$$
else
    warn "SAPHanaSR-showAttr command was not found in PATH"
fi

rm -f \
    /tmp/cib.$$ \
    /tmp/crm_config.$$ \
    /tmp/crm_mon_resources.$$

printf '\n============================================================\n'
printf 'Preflight summary for %s\n' "$HOST"
printf 'Mandatory failures: %s\n' "$FAILURES"
printf 'Warnings:           %s\n' "$WARNINGS"
printf '============================================================\n'

if [[ "$FAILURES" -gt 0 ]]; then
    printf 'RESULT: NOT READY — correct all FAIL items before proceeding.\n'
    exit 1
fi

printf 'RESULT: READY — no mandatory prerequisite failures were found.\n'
printf 'Review WARN items before proceeding.\n'
exit 0