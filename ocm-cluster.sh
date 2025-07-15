#!/bin/bash
#
# OCM Cluster Management for Terraform Assisted Install
# Provides OCM-based cluster operations similar to python-assisted-install
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$SCRIPT_DIR/tmp"

# Ensure tmp directory exists
mkdir -p "$TMP_DIR"

# Color output functions
print_colored() {
    local message="$1"
    local level="${2:-INFO}"
    
    case "$level" in
        "ERROR")   echo -e "\033[31m❌ $message\033[0m" ;;
        "WARNING") echo -e "\033[33m⚠️  $message\033[0m" ;;
        "SUCCESS") echo -e "\033[32m✅ $message\033[0m" ;;
        "INFO")    echo -e "\033[36mℹ️  $message\033[0m" ;;
        *)         echo "$message" ;;
    esac
}

# Get OCM token
get_ocm_token() {
    local token
    if token=$(ocm token 2>/dev/null) && [[ -n "$token" && "$token" != "null" ]]; then
        echo "$token"
        return 0
    else
        print_colored "No valid OCM token. Run ./ocm-auth.sh first" "ERROR"
        return 1
    fi
}

# Make authenticated API request
api_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local output_file="$4"
    
    local token
    if ! token=$(get_ocm_token); then
        return 1
    fi
    
    local url="https://api.openshift.com/api/assisted-install/v2/$endpoint"
    local curl_opts=(
        -s -w "%{http_code}"
        -H "Authorization: Bearer $token"
        -H "Content-Type: application/json"
    )
    
    if [[ "$method" == "POST" && -n "$data" ]]; then
        curl_opts+=(-X POST -d "$data")
    elif [[ "$method" == "PATCH" && -n "$data" ]]; then
        curl_opts+=(-X PATCH -d "$data")
    elif [[ "$method" == "DELETE" ]]; then
        curl_opts+=(-X DELETE)
    fi
    
    if [[ -n "$output_file" ]]; then
        curl_opts+=(-o "$output_file")
    else
        curl_opts+=(-o "$TMP_DIR/api_response.json")
    fi
    
    local response
    response=$(curl "${curl_opts[@]}" "$url" 2>/dev/null)
    local http_code="${response: -3}"
    
    echo "$http_code"
}

# List all clusters
list_clusters() {
    print_colored "Listing OpenShift clusters..." "INFO"
    
    local http_code
    if http_code=$(api_request "GET" "clusters" "" "$TMP_DIR/clusters.json"); then
        if [[ "$http_code" == "200" ]]; then
            local cluster_count=$(jq length "$TMP_DIR/clusters.json" 2>/dev/null || echo "0")
            print_colored "Found $cluster_count clusters" "SUCCESS"
            
            if [[ "$cluster_count" != "0" ]]; then
                echo
                printf "%-20s %-15s %-12s %-10s %s\n" "NAME" "STATUS" "VERSION" "NODES" "ID"
                echo "$(printf '%.80s' "$(printf -- '-%.0s' {1..80})")"
                
                jq -r '.[] | "\(.name)|\(.status)|\(.openshift_version // "unknown")|\(.host_networks | length)|\(.id)"' \
                    "$TMP_DIR/clusters.json" 2>/dev/null | \
                while IFS='|' read -r name status version nodes id; do
                    printf "%-20s %-15s %-12s %-10s %s\n" \
                        "${name:0:19}" "${status:0:14}" "${version:0:11}" "$nodes" "${id:0:8}..."
                done
            fi
            return 0
        else
            print_colored "API returned HTTP $http_code" "ERROR"
            [[ -f "$TMP_DIR/clusters.json" ]] && jq . "$TMP_DIR/clusters.json" 2>/dev/null
            return 1
        fi
    else
        print_colored "Failed to connect to API" "ERROR"
        return 1
    fi
}

# Get cluster details
get_cluster() {
    local cluster_id="$1"
    
    if [[ -z "$cluster_id" ]]; then
        print_colored "Usage: $0 get <cluster-id>" "ERROR"
        return 1
    fi
    
    print_colored "Getting cluster details for $cluster_id..." "INFO"
    
    local http_code
    if http_code=$(api_request "GET" "clusters/$cluster_id" "" "$TMP_DIR/cluster_detail.json"); then
        if [[ "$http_code" == "200" ]]; then
            print_colored "Cluster details:" "SUCCESS"
            echo
            
            # Parse and display key information
            local name status version base_domain
            name=$(jq -r '.name // "unknown"' "$TMP_DIR/cluster_detail.json")
            status=$(jq -r '.status // "unknown"' "$TMP_DIR/cluster_detail.json")
            version=$(jq -r '.openshift_version // "unknown"' "$TMP_DIR/cluster_detail.json")
            base_domain=$(jq -r '.base_dns_domain // "unknown"' "$TMP_DIR/cluster_detail.json")
            
            echo "Name:           $name"
            echo "Status:         $status"
            echo "Version:        $version"
            echo "Base Domain:    $base_domain"
            echo "Cluster ID:     $cluster_id"
            echo
            
            # Show hosts if any
            local host_count=$(jq '.host_networks | length' "$TMP_DIR/cluster_detail.json" 2>/dev/null || echo "0")
            echo "Hosts:          $host_count"
            
            if [[ "$host_count" != "0" ]]; then
                echo
                echo "Host Networks:"
                jq -r '.host_networks[]? | "  - CIDR: \(.cidr), Host ID: \(.host_ids[0] // "none")"' \
                    "$TMP_DIR/cluster_detail.json" 2>/dev/null || true
            fi
            
            # Save formatted output
            jq . "$TMP_DIR/cluster_detail.json" > "$TMP_DIR/cluster_${cluster_id}_formatted.json"
            print_colored "Full details saved to: $TMP_DIR/cluster_${cluster_id}_formatted.json" "INFO"
            
            return 0
        else
            print_colored "API returned HTTP $http_code" "ERROR"
            [[ -f "$TMP_DIR/cluster_detail.json" ]] && jq . "$TMP_DIR/cluster_detail.json" 2>/dev/null
            return 1
        fi
    else
        print_colored "Failed to connect to API" "ERROR"
        return 1
    fi
}

# Monitor cluster installation
monitor_cluster() {
    local cluster_id="$1"
    local interval="${2:-30}"
    
    if [[ -z "$cluster_id" ]]; then
        print_colored "Usage: $0 monitor <cluster-id> [interval-seconds]" "ERROR"
        return 1
    fi
    
    print_colored "Monitoring cluster $cluster_id (checking every ${interval}s, Ctrl+C to stop)..." "INFO"
    echo
    
    while true; do
        local http_code
        if http_code=$(api_request "GET" "clusters/$cluster_id" "" "$TMP_DIR/monitor.json"); then
            if [[ "$http_code" == "200" ]]; then
                local status timestamp
                status=$(jq -r '.status // "unknown"' "$TMP_DIR/monitor.json")
                timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                
                echo "[$timestamp] Status: $status"
                
                # Check for completion or error states
                case "$status" in
                    "installed")
                        print_colored "Cluster installation completed successfully!" "SUCCESS"
                        break
                        ;;
                    "error"|"cancelled")
                        print_colored "Cluster installation failed with status: $status" "ERROR"
                        local status_info=$(jq -r '.status_info // "No additional information"' "$TMP_DIR/monitor.json")
                        echo "Details: $status_info"
                        break
                        ;;
                esac
            else
                print_colored "API returned HTTP $http_code" "WARNING"
            fi
        else
            print_colored "Failed to get cluster status" "WARNING"
        fi
        
        sleep "$interval"
    done
}

# Delete cluster
delete_cluster() {
    local cluster_id="$1"
    
    if [[ -z "$cluster_id" ]]; then
        print_colored "Usage: $0 delete <cluster-id>" "ERROR"
        return 1
    fi
    
    print_colored "WARNING: This will delete cluster $cluster_id" "WARNING"
    read -p "Are you sure? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        print_colored "Deleting cluster $cluster_id..." "INFO"
        
        local http_code
        if http_code=$(api_request "DELETE" "clusters/$cluster_id"); then
            if [[ "$http_code" == "204" ]]; then
                print_colored "Cluster deleted successfully" "SUCCESS"
                return 0
            else
                print_colored "Failed to delete cluster (HTTP $http_code)" "ERROR"
                return 1
            fi
        else
            print_colored "Failed to connect to API" "ERROR"
            return 1
        fi
    else
        print_colored "Operation cancelled" "INFO"
        return 0
    fi
}

# Show help
show_help() {
    echo "OCM Cluster Management for Terraform Assisted Install"
    echo "=============================================="
    echo
    echo "USAGE:"
    echo "  $0 <command> [arguments]"
    echo
    echo "COMMANDS:"
    echo "  list                     List all clusters"
    echo "  get <cluster-id>         Get detailed cluster information"  
    echo "  monitor <cluster-id>     Monitor cluster installation progress"
    echo "  delete <cluster-id>      Delete a cluster"
    echo "  help                     Show this help message"
    echo
    echo "EXAMPLES:"
    echo "  $0 list"
    echo "  $0 get abc123de-f456-7890-abcd-ef1234567890"
    echo "  $0 monitor abc123de-f456-7890-abcd-ef1234567890"
    echo "  $0 delete abc123de-f456-7890-abcd-ef1234567890"
    echo
    echo "PREREQUISITES:"
    echo "  - OCM CLI installed and authenticated (run ./ocm-auth.sh)"
    echo "  - jq command available for JSON processing"
    echo
}

# Main function
main() {
    local command="$1"
    
    # Check prerequisites
    if ! command -v jq >/dev/null 2>&1; then
        print_colored "jq command not found. Please install jq first." "ERROR"
        exit 1
    fi
    
    if ! command -v ocm >/dev/null 2>&1; then
        print_colored "OCM CLI not found. Please run ./ocm-auth.sh first." "ERROR"
        exit 1
    fi
    
    case "$command" in
        "list")
            list_clusters
            ;;
        "get")
            get_cluster "$2"
            ;;
        "monitor")
            monitor_cluster "$2" "$3"
            ;;
        "delete")
            delete_cluster "$2"
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            print_colored "Unknown command: $command" "ERROR"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
