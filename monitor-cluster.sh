#!/bin/bash

# monitor-cluster.sh - Monitor cluster status using the Assisted Installer API
# Enhanced with OCM support like python-assisted-install

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Get API token (prefer OCM, fallback to terraform.tfvars)
get_api_token() {
    # Try OCM first (like python-assisted-install)
    if command -v ocm >/dev/null 2>&1; then
        local ocm_token
        if ocm_token=$(ocm token 2>/dev/null) && [[ -n "$ocm_token" && "$ocm_token" != "null" ]]; then
            echo "$ocm_token"
            return 0
        fi
    fi
    
    # Fallback to terraform.tfvars
    if [[ -f "$SCRIPT_DIR/terraform.tfvars" ]]; then
        local tf_token
        tf_token=$(grep '^api_token' "$SCRIPT_DIR/terraform.tfvars" | cut -d'"' -f2)
        if [[ -n "$tf_token" && "$tf_token" != "YOUR_REDHAT_API_TOKEN_HERE" ]]; then
            echo "$tf_token"
            return 0
        fi
    fi
    
    print_colored "No valid API token found. Run ./ocm-auth.sh or update terraform.tfvars" "ERROR"
    return 1
}

# Check if we have the required files
if [[ ! -f "$SCRIPT_DIR/tmp/cluster_response.json" ]]; then
    print_colored "No cluster found. Run terraform apply first." "ERROR"
    exit 1
fi

# Extract configuration
API_TOKEN=$(get_api_token)
if [[ -z "$API_TOKEN" ]]; then
    exit 1
fi

ASSISTED_SERVICE_URL="https://api.openshift.com"
CLUSTER_ID=$(jq -r '.id' "$SCRIPT_DIR/tmp/cluster_response.json")

print_colored "Using OCM-compatible monitoring (like python-assisted-install)" "INFO"

echo "Monitoring cluster: $CLUSTER_ID"
echo "Service URL: $ASSISTED_SERVICE_URL"
echo ""

# Function to get cluster status
get_cluster_status() {
    curl -s -X GET \
        -H "Authorization: Bearer $API_TOKEN" \
        "$ASSISTED_SERVICE_URL/api/assisted-install/v2/clusters/$CLUSTER_ID" \
        -o tmp/current_status.json \
        -w "%{http_code}"
}

# Function to get cluster hosts
get_cluster_hosts() {
    curl -s -X GET \
        -H "Authorization: Bearer $API_TOKEN" \
        "$ASSISTED_SERVICE_URL/api/assisted-install/v2/clusters/$CLUSTER_ID/hosts" \
        -o tmp/current_hosts.json \
        -w "%{http_code}"
}

# Monitor loop
while true; do
    echo "$(date): Checking cluster status..."
    
    # Get cluster status
    STATUS_CODE=$(get_cluster_status)
    if [ "$STATUS_CODE" = "200" ]; then
        STATUS=$(jq -r '.status' tmp/current_status.json)
        STATUS_INFO=$(jq -r '.status_info' tmp/current_status.json)
        
        echo "  Cluster Status: $STATUS"
        echo "  Status Info: $STATUS_INFO"
        
        # Get hosts status
        HOST_STATUS_CODE=$(get_cluster_hosts)
        if [ "$HOST_STATUS_CODE" = "200" ]; then
            HOST_COUNT=$(jq length tmp/current_hosts.json)
            echo "  Registered Hosts: $HOST_COUNT"
            
            if [ "$HOST_COUNT" -gt 0 ]; then
                echo "  Host Details:"
                jq -r '.[] | "    \(.requested_hostname // .id): \(.status) (\(.role))"' tmp/current_hosts.json
            fi
        fi
        
        # Check if installation is complete
        if [ "$STATUS" = "installed" ]; then
            echo ""
            echo "🎉 Cluster installation completed successfully!"
            
            API_VIP=$(jq -r '.api_vip // "Not available"' tmp/current_status.json)
            INGRESS_VIP=$(jq -r '.ingress_vip // "Not available"' tmp/current_status.json)
            CONSOLE_URL=$(jq -r '.console_url // "Not available"' tmp/current_status.json)
            
            echo "  API VIP: $API_VIP"
            echo "  Ingress VIP: $INGRESS_VIP" 
            echo "  Console URL: $CONSOLE_URL"
            break
        elif [ "$STATUS" = "error" ]; then
            echo ""
            echo "❌ Cluster installation failed!"
            echo "Check the cluster details for more information:"
            jq '.' tmp/current_status.json
            break
        fi
    else
        echo "  Error getting cluster status (HTTP $STATUS_CODE)"
    fi
    
    echo "  Waiting 30 seconds before next check..."
    echo ""
    sleep 30
done
