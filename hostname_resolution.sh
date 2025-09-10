#!/bin/bash

# Function to check DNS resolution using nslookup
check_dns_resolution() {
    local host="$1"
    # Capture all IP addresses returned by nslookup
    local dns_ips=$(nslookup "$host" | awk '/^Address: / { print $2 }')
    echo "$dns_ips"
}

# Function to check /etc/hosts resolution
check_hosts_file_resolution() {
    local host="$1"
    # Capture IP addresses for the host from /etc/hosts
    local hosts_ips=$(awk -v host="$host" '$0 !~ /^#/ { for (i=2; i<=NF; i++) if ($i == host) print $1 }' /etc/hosts)
    echo "$hosts_ips"
}

# Function to compare DNS and /etc/hosts resolutions
compare_resolutions() {
    local host="$1"
    local dns_ips=$(check_dns_resolution "$host")
    local hosts_ips=$(check_hosts_file_resolution "$host")

    if [ -n "$dns_ips" ]; then
        echo "DNS $host: $dns_ips"
    # else
        # echo "DNS resolution for $host failed or not found."
    fi

    if [ -n "$hosts_ips" ]; then
        echo "/etc/hosts $host: $hosts_ips"
    # else
        # echo "/etc/hosts resolution for $host not found."
    fi

    # Compare each DNS IP with /etc/hosts IPs
    local mismatch_found=false
    for dns_ip in $dns_ips; do
        if ! echo "$hosts_ips" | grep -q "$dns_ip"; then
            mismatch_found=true
        fi
    done

    if [ "$mismatch_found" = true ]; then
        echo "====== Resolution mismatch for $host!"
    # else
        # echo "Resolution matches for $host."
    fi
}

# Check if filename is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 filename"
    exit 1
fi

filename="$1"

# Check if file exists
if [ ! -f "$filename" ]; then
    echo "File not found: $filename"
    exit 1
fi

# Read hosts from file and compare resolutions
while IFS= read -r host; do
    if [ -n "$host" ]; then
        compare_resolutions "$host"
    fi
done < "$filename"
