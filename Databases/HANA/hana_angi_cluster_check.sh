#!/usr/bin/env bash
#
# azure_suse_pacemaker_preflight.sh
#
# Read-only validation for a Pacemaker cluster on SLES for SAP Applications
# in Azure using Azure Fence Agent and Managed Identity.
#
# Validates:
#   - SLES for SAP, Pacemaker, Corosync, and required packages
#   - Basic cluster health and two-node membership
#   - Azure Fence Agent and fence_azure_arm configuration
#   - System-assigned Managed Identity through Azure IMDS
#   - Optional Azure Scheduled Events resource integration
#
# Run as root:
#   ./azure_suse_pacemaker_preflight.sh
#
# Optional:
#   ./azure_suse_pacemaker_preflight.sh \
#       --nodes sap-cl1,sap-cl2 \
#       --resource-group my-resource-group \
#       --subscription-id 00000000-0000-0000-0000-000000000000
#
# The script does not modify Pacemaker, Azure, systemd, or fencing settings.

set -uo pipefail

NODES=""
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
FAILURES=0
WARNINGS=0

# ---------------------------------------------------------------------------
# Color support
#
# Colors are enabled only when stdout is an interactive terminal. Set
# NO_COLOR=1 before execution to disable ANSI colors explicitly.
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
    COLOR_RESET=$'\033[0m'
    COLOR_GREEN=$'\033[0;32m'
    COLOR_YELLOW=$'\033[1;33m'
    COLOR_BLUE=$'\033[0;34m'
    COLOR_RED=$'\033[0;31m'
else
    COLOR_RESET=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_RED=""
fi

usage() {
    cat <<'EOF'
Usage:
  azure_suse_pacemaker_preflight.sh [options]

Options:
  --nodes <node1,node2>              Optional expected cluster node names.
  --resource-group <name>            Optional expected Azure resource group.
  --subscription-id <GUID>           Optional expected Azure subscription ID.
  -h, --help                         Display this help text.

EOF
}

pass() {
    printf '%sPASS%s  %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

warn() {
    printf '%sWARN%s  %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    printf '%sFAIL%s  %s\n' "$COLOR_RED" "$COLOR_RESET" "$*"
    FAILURES=$((FAILURES + 1))
}

info() {
    printf '%sINFO%s  %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$*"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

rpm_installed() {
    rpm -q "$1" >/dev/null 2>&1
}

require_command() {
    local command_name="$1"

    if command_exists "$command_name"; then
        pass "Command available: ${command_name}"
    else
        fail "Required command is missing: ${command_name}"
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

get_cluster_property() {
    local property="$1"
    local value

    value="$(crm configure get_property "$property" 2>/dev/null)" || return 1
    printf '%s\n' "$value"
}

get_resource_parameter() {
    local resource="$1"
    local parameter="$2"

    crm_resource --resource "$resource" \
        --get-parameter "$parameter" 2>/dev/null || true
}

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

# Query the Azure Instance Metadata Service for system-assigned Managed Identity
# information. This is a local link-local endpoint and does not expose a secret.
# Queries basic Managed Identity metadata. This commonly returns tenantId.
get_managed_identity_info() {
    curl \
        --silent \
        --show-error \
        --fail \
        --connect-timeout 3 \
        --max-time 10 \
        --noproxy "*" \
        --header "Metadata: true" \
        "http://169.254.169.254/metadata/identity/info?api-version=2018-02-01"
}

# Requests an Azure Resource Manager access token through IMDS.
#
# A successful response containing access_token proves that Managed Identity
# authentication is operational. Never print, store, or log this response
# because it contains a sensitive bearer token.
get_managed_identity_token() {
    curl \
        --silent \
        --show-error \
        --fail \
        --connect-timeout 3 \
        --max-time 10 \
        --noproxy "*" \
        --header "Metadata: true" \
        "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F"
}


while [[ $# -gt 0 ]]; do
    case "$1" in
        --nodes)
            NODES="${2:-}"
            shift 2
            ;;
        --resource-group)
            RESOURCE_GROUP="${2:-}"
            shift 2
            ;;
        --subscription-id)
            SUBSCRIPTION_ID="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf '%sUnknown argument: %s%s\n\n' \
                "$COLOR_RED" "$1" "$COLOR_RESET" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    printf '%sThis script must be run as root.%s\n' \
        "$COLOR_RED" "$COLOR_RESET" >&2
    exit 2
fi

HOST="$(hostname -s)"

printf '\n============================================================\n'
printf 'Azure SUSE Pacemaker cluster preflight\n'
printf 'Host: %s\n' "$HOST"
printf '============================================================\n'

info "This script is read-only. It does not alter CRM, Azure, systemd, or fencing configuration."

# ===========================================================================
# Operating system and required command validation
# ===========================================================================
printf '\n--- Operating system and commands ---\n'

for command_name in \
    rpm systemctl crm crm_mon crm_node crm_resource cibadmin \
    getent awk grep sed curl; do
    require_command "$command_name"
done

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    pass "Operating system detected: ${PRETTY_NAME:-unknown}"

    if awk "BEGIN {exit !(${VERSION_ID:-0} >= 15.4)}" 2>/dev/null; then
        pass "SLES version meets the documented SLES for SAP 15 SP4+ baseline"
    else
        warn "Detected SLES version may be below the documented SLES for SAP 15 SP4+ baseline"
    fi
else
    fail "Cannot read /etc/os-release"
fi

if is_sles_for_sap; then
    pass "SLES for SAP Applications product detected in /etc/products.d"
else
    warn "SLES for SAP Applications product was not detected in /etc/products.d"
fi

# ===========================================================================
# Package validation
# ===========================================================================
printf '\n--- Pacemaker and fencing packages ---\n'

for package in pacemaker resource-agents socat fence-agents-azure-arm; do
    if rpm_installed "$package"; then
        pass "Package installed: ${package} ($(rpm -q "$package"))"
    else
        fail "Required package is missing: ${package}"
    fi
done

if crm ra meta "stonith:fence_azure_arm" >/dev/null 2>&1 ||
   command_exists fence_azure_arm; then
    pass "Azure Fence Agent is available"
else
    fail "Azure Fence Agent is unavailable"
fi

if crm ra meta "ocf:heartbeat:azure-events-az" >/dev/null 2>&1; then
    pass "azure-events-az resource agent is available"
else
    warn "azure-events-az resource agent is unavailable"
fi

# ===========================================================================
# Azure Managed Identity validation
# ===========================================================================
printf '\n--- Azure Managed Identity ---\n'

# The identity-info endpoint typically provides tenant information. It might
# not return a principalId, so principalId is not used as a mandatory check.
if MANAGED_IDENTITY_INFO="$(get_managed_identity_info 2>/tmp/managed_identity_info_error.$$)"; then
    if grep -qE '"tenantId"[[:space:]]*:[[:space:]]*"[0-9a-fA-F-]+"' \
        <<< "$MANAGED_IDENTITY_INFO"; then

        MANAGED_IDENTITY_TENANT_ID="$(
            sed -n 's/.*"tenantId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
                <<< "$MANAGED_IDENTITY_INFO"
        )"

        pass "Managed Identity tenant ID is available through Azure IMDS"
        info "Managed Identity tenant ID: ${MANAGED_IDENTITY_TENANT_ID}"
    else
        warn "Azure IMDS identity information does not contain a tenant ID"
    fi
else
    warn "Unable to query Azure IMDS identity information endpoint"
    info "Azure IMDS error: $(cat /tmp/managed_identity_info_error.$$ 2>/dev/null)"
fi

rm -f /tmp/managed_identity_info_error.$$

# Requesting a token is the functional Managed Identity validation. The
# response is deliberately never displayed because it includes access_token.
if MANAGED_IDENTITY_TOKEN_RESPONSE="$(get_managed_identity_token 2>/tmp/managed_identity_token_error.$$)"; then
    if grep -qE '"access_token"[[:space:]]*:' \
        <<< "$MANAGED_IDENTITY_TOKEN_RESPONSE"; then
        pass "Managed Identity can obtain an Azure Resource Manager access token"
    else
        fail "Azure IMDS token endpoint responded without an access_token"
    fi
else
    fail "Managed Identity could not obtain an Azure Resource Manager access token"
    info "Azure IMDS error: $(cat /tmp/managed_identity_token_error.$$ 2>/dev/null)"
fi

# Explicitly remove the token response from the shell variable. Do not log it.
unset MANAGED_IDENTITY_TOKEN_RESPONSE

rm -f /tmp/managed_identity_token_error.$$


# ===========================================================================
# Pacemaker and Corosync cluster validation
# ===========================================================================
printf '\n--- Pacemaker and Corosync cluster ---\n'

check_service_active corosync
check_service_active pacemaker

if crm_mon -1 >/tmp/crm_mon.$$ 2>&1; then
    pass "Pacemaker cluster is queryable"
    grep -E 'Online:|OFFLINE:|RemoteOnline:' /tmp/crm_mon.$$ \
        | sed "s/^/${COLOR_BLUE}INFO${COLOR_RESET}  /"
else
    fail "crm_mon could not query the cluster"
fi

rm -f /tmp/crm_mon.$$

if cibadmin -Q >/tmp/cib.$$ 2>/dev/null; then
    pass "Cluster Information Base (CIB) is readable"
else
    fail "Unable to read the Cluster Information Base"
    : >/tmp/cib.$$
fi

mapfile -t CLUSTER_NODES < <(
    crm_node -l 2>/dev/null \
        | awk '{print $2}' \
        | sort -u
)

if [[ ${#CLUSTER_NODES[@]} -eq 2 ]]; then
    pass "Two cluster nodes detected: ${CLUSTER_NODES[*]}"
elif [[ ${#CLUSTER_NODES[@]} -gt 2 ]]; then
    warn "More than two cluster nodes detected: ${CLUSTER_NODES[*]}"
else
    fail "Expected at least two cluster nodes; detected: ${CLUSTER_NODES[*]:-none}"
fi

if [[ -n "$NODES" ]]; then
    IFS=',' read -r -a EXPECTED_NODES <<< "$NODES"

    for expected_node in "${EXPECTED_NODES[@]}"; do
        if printf '%s\n' "${CLUSTER_NODES[@]}" | grep -qx "$expected_node"; then
            pass "Expected cluster node found: ${expected_node}"
        else
            fail "Expected cluster node not found: ${expected_node}"
        fi
    done
fi

for cluster_node in "${CLUSTER_NODES[@]}"; do
    if getent hosts "$cluster_node" >/dev/null 2>&1; then
        pass "Hostname resolution works for cluster node: ${cluster_node}"
    else
        fail "Hostname resolution failed for cluster node: ${cluster_node}"
    fi
done

TOKEN_VALUE="$(crm corosync get totem.token 2>/dev/null || true)"

if [[ "$TOKEN_VALUE" == "30000" ]]; then
    pass "Corosync totem.token is configured to 30000"
elif [[ -n "$TOKEN_VALUE" ]]; then
    warn "Corosync totem.token is '${TOKEN_VALUE}', not the documented value of 30000"
else
    warn "Unable to read Corosync totem.token"
fi

STONITH_ENABLED="$(get_cluster_property stonith-enabled || true)"

if [[ "$STONITH_ENABLED" == "true" ]]; then
    pass "Cluster property stonith-enabled=true"
else
    fail "Cluster property stonith-enabled must be true; current value: '${STONITH_ENABLED:-unset}'"
fi

STONITH_TIMEOUT="$(get_cluster_property stonith-timeout || true)"

if [[ "$STONITH_TIMEOUT" == "900" || "$STONITH_TIMEOUT" == "900s" ]]; then
    pass "Cluster property stonith-timeout=${STONITH_TIMEOUT}"
elif [[ -n "$STONITH_TIMEOUT" ]]; then
    warn "stonith-timeout is '${STONITH_TIMEOUT}', while Microsoft guidance uses 900 seconds"
else
    warn "Cluster property stonith-timeout is not explicitly configured"
fi

# ===========================================================================
# Pacemaker delayed startup validation
# ===========================================================================
printf '\n--- Pacemaker startup delay ---\n'

if systemctl is-enabled --quiet pacemaker.timer; then
    pass "pacemaker.timer is enabled"
else
    warn "pacemaker.timer is not enabled"
fi

if [[ -r /etc/systemd/system/pacemaker.timer ]]; then
    if grep -qE '^OnBootSec=216$' /etc/systemd/system/pacemaker.timer; then
        pass "pacemaker.timer uses the documented OnBootSec=216 delay"
    else
        warn "pacemaker.timer exists but OnBootSec=216 was not found"
    fi
else
    warn "Custom /etc/systemd/system/pacemaker.timer file was not found"
fi

# ===========================================================================
# Azure Fence Agent validation
# ===========================================================================
printf '\n--- Azure Fence Agent configuration ---\n'

if crm configure show >/tmp/crm_config.$$ 2>/dev/null; then
    pass "Pacemaker configuration is queryable"
else
    fail "Unable to read Pacemaker configuration with 'crm configure show'"
    : >/tmp/crm_config.$$
fi

mapfile -t AZURE_FENCE_RESOURCES < <(
    awk '$1 == "primitive" && $0 ~ /fence_azure_arm/ {print $2}' \
        /tmp/crm_config.$$
)

if [[ ${#AZURE_FENCE_RESOURCES[@]} -eq 0 ]]; then
    fail "No Pacemaker STONITH resource using fence_azure_arm is configured"
elif [[ ${#AZURE_FENCE_RESOURCES[@]} -gt 1 ]]; then
    warn "More than one Azure Fence Agent resource is configured: ${AZURE_FENCE_RESOURCES[*]}"
else
    pass "Azure Fence Agent resource configured: ${AZURE_FENCE_RESOURCES[0]}"
fi

for fence_resource in "${AZURE_FENCE_RESOURCES[@]}"; do
    FENCE_CFG="$(crm_object_block "$fence_resource")"

    MSI_VALUE="$(get_resource_parameter "$fence_resource" "msi")"

    if [[ "$MSI_VALUE" == "true" ]]; then
        pass "Azure Fence Agent uses Managed Identity authentication: msi=true"
    else
        fail "Azure Fence Agent must use Managed Identity authentication: msi=true"
    fi

    if [[ -n "${MANAGED_IDENTITY_INFO:-}" ]]; then
        pass "Azure Fence Agent has an available system-assigned Managed Identity"
    else
        fail "Azure Fence Agent is configured for Managed Identity but the local Managed Identity check failed"
    fi

    FENCE_RG="$(get_resource_parameter "$fence_resource" "resourceGroup")"

    if [[ -n "$FENCE_RG" && "$FENCE_RG" != "default" ]]; then
        pass "Azure Fence Agent resourceGroup is configured"

        if [[ -n "$RESOURCE_GROUP" && "$FENCE_RG" != "$RESOURCE_GROUP" ]]; then
            fail "Azure Fence Agent resourceGroup '${FENCE_RG}' does not match expected '${RESOURCE_GROUP}'"
        fi
    else
        fail "Azure Fence Agent resourceGroup is not configured"
    fi

    FENCE_SUBSCRIPTION="$(get_resource_parameter "$fence_resource" "subscriptionId")"

    if [[ -n "$FENCE_SUBSCRIPTION" && "$FENCE_SUBSCRIPTION" != "default" ]]; then
        pass "Azure Fence Agent subscriptionId is configured"

        if [[ -n "$SUBSCRIPTION_ID" && "$FENCE_SUBSCRIPTION" != "$SUBSCRIPTION_ID" ]]; then
            fail "Azure Fence Agent subscriptionId does not match the supplied expected subscription ID"
        fi
    else
        fail "Azure Fence Agent subscriptionId is not configured"
    fi

    HOST_MAP="$(get_resource_parameter "$fence_resource" "pcmk_host_map")"

    if [[ -n "$HOST_MAP" && "$HOST_MAP" != "default" ]]; then
        pass "Azure Fence Agent pcmk_host_map is configured"

        for cluster_node in "${CLUSTER_NODES[@]}"; do
            if grep -qE "(^|;)${cluster_node}:" <<< "$HOST_MAP"; then
                pass "Azure VM mapping exists for cluster node: ${cluster_node}"
            else
                fail "Azure VM mapping is missing for cluster node: ${cluster_node}"
            fi
        done
    else
        fail "Azure Fence Agent pcmk_host_map is not configured"
    fi

    for parameter_check in \
        "power_timeout:240" \
        "pcmk_reboot_timeout:900" \
        "pcmk_monitor_timeout:120" \
        "pcmk_monitor_retries:4" \
        "pcmk_action_limit:3" \
        "pcmk_delay_max:15"; do

        parameter_name="${parameter_check%%:*}"
        expected_value="${parameter_check##*:}"
        actual_value="$(get_resource_parameter "$fence_resource" "$parameter_name")"

        if [[ "$actual_value" == "$expected_value" ]]; then
            pass "Azure Fence Agent ${parameter_name}=${expected_value}"
        else
            warn "Azure Fence Agent ${parameter_name} is '${actual_value:-unset}', while Microsoft guidance uses ${expected_value}"
        fi
    done

    if grep -qE 'op monitor interval=3600s?[[:space:]]+timeout=120s?' <<< "$FENCE_CFG"; then
        pass "Azure Fence Agent monitor operation uses interval=3600 and timeout=120"
    else
        warn "Could not confirm Azure Fence Agent monitor interval=3600 timeout=120"
    fi
done

# ===========================================================================
# Optional Azure Scheduled Events validation
# ===========================================================================
printf '\n--- Azure Scheduled Events integration ---\n'

HEALTH_EVENT_RESOURCE="health-azure-events"
HEALTH_EVENT_CLONE="health-azure-events-cln"
HEALTH_LOCATION="loc_azure_health"

HEALTH_EVENT_CFG="$(crm_object_block "$HEALTH_EVENT_RESOURCE")"
HEALTH_EVENT_CLONE_CFG="$(crm_object_block "$HEALTH_EVENT_CLONE")"
HEALTH_LOCATION_CFG="$(crm_object_block "$HEALTH_LOCATION")"

if [[ -z "$HEALTH_EVENT_CFG" ]]; then
    info "Azure Scheduled Events resource is not configured; health-azure validation is skipped"
else
    pass "Azure Scheduled Events resource is configured: ${HEALTH_EVENT_RESOURCE}"

    NODE_HEALTH_STRATEGY="$(get_cluster_property node-health-strategy || true)"

    if [[ "$NODE_HEALTH_STRATEGY" == "custom" ]]; then
        pass "Cluster property node-health-strategy=custom"
    else
        fail "Azure Scheduled Events requires node-health-strategy=custom; current value: '${NODE_HEALTH_STRATEGY:-unset}'"
    fi

    if grep -qE "^primitive[[:space:]]+${HEALTH_EVENT_RESOURCE}[[:space:]]+(ocf:heartbeat:)?azure-events-az" <<< "$HEALTH_EVENT_CFG"; then
        pass "health-azure-events uses azure-events-az resource agent"
    else
        fail "health-azure-events is not configured with azure-events-az"
    fi

    if grep -qE "^clone[[:space:]]+${HEALTH_EVENT_CLONE}[[:space:]]+${HEALTH_EVENT_RESOURCE}" <<< "$HEALTH_EVENT_CLONE_CFG"; then
        pass "Azure Scheduled Events clone is configured"
    else
        fail "Azure Scheduled Events clone is missing"
    fi

    if grep -q 'allow-unhealthy-nodes=true' <<< "$HEALTH_EVENT_CLONE_CFG"; then
        pass "Azure Scheduled Events clone allows unhealthy nodes"
    else
        warn "Could not confirm allow-unhealthy-nodes=true for Azure Scheduled Events clone"
    fi

    if grep -q "#health-azure" <<< "$HEALTH_LOCATION_CFG"; then
        pass "Azure health location constraint is configured"
    else
        fail "Azure health location constraint ${HEALTH_LOCATION} is missing or invalid"
    fi

    if [[ -n "${MANAGED_IDENTITY_INFO:-}" ]]; then
        pass "azure-events-az has an available local Managed Identity"
    else
        fail "azure-events-az is configured but local Managed Identity validation failed"
    fi
fi

# ===========================================================================
# Runtime status validation
# ===========================================================================
printf '\n--- Runtime status ---\n'

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

for fence_resource in "${AZURE_FENCE_RESOURCES[@]}"; do
    FENCE_RUNTIME_NODE="$(
        awk -v resource="$fence_resource" '
            index($0, resource) && $0 ~ /Started/ {
                print $NF
                exit
            }
        ' /tmp/crm_mon_resources.$$
    )"

    if [[ -n "$FENCE_RUNTIME_NODE" ]]; then
        pass "Azure Fence Agent resource is Started on: ${FENCE_RUNTIME_NODE}"
    else
        warn "Azure Fence Agent resource ${fence_resource} is not reported as Started"
    fi
done

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
    printf '%sRESULT: NOT READY — correct all FAIL items before proceeding.%s\n' \
        "$COLOR_RED" "$COLOR_RESET"
    exit 1
fi

printf '%sRESULT: READY — no mandatory prerequisite failures were found.%s\n' \
    "$COLOR_GREEN" "$COLOR_RESET"
printf '%sReview WARN items before proceeding.%s\n' \
    "$COLOR_YELLOW" "$COLOR_RESET"
exit 0
