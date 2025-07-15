#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo -e "${BLUE}[SECTION]${NC} $1"
}

# Function to run terraform command with error handling
run_terraform() {
    local cmd="$1"
    local description="$2"
    
    print_status "$description"
    if terraform $cmd; then
        print_status "$description - SUCCESS"
        return 0
    else
        print_error "$description - FAILED"
        return 1
    fi
}

# Test cycle counter
cycle=1
max_cycles=5

while [ $cycle -le $max_cycles ]; do
    print_section "=== TEST CYCLE $cycle ==="
    
    # Clean start
    print_status "Cleaning up any existing state..."
    rm -rf .terraform.lock.hcl .terraform/ terraform.tfstate* tmp/
    
    # Initialize
    if ! run_terraform "init" "Initializing Terraform"; then
        print_error "Init failed in cycle $cycle"
        exit 1
    fi
    
    # Validate
    if ! run_terraform "validate" "Validating configuration"; then
        print_error "Validation failed in cycle $cycle"
        exit 1
    fi
    
    # Format
    run_terraform "fmt -recursive" "Formatting code"
    
    # Plan
    if ! run_terraform "plan -out=tfplan" "Creating execution plan"; then
        print_error "Planning failed in cycle $cycle"
        exit 1
    fi
    
    # Apply
    if ! run_terraform "apply -auto-approve tfplan" "Applying configuration"; then
        print_error "Apply failed in cycle $cycle"
        exit 1
    fi
    
    # Show outputs
    print_status "Showing outputs..."
    terraform output
    
    # Destroy
    if ! run_terraform "destroy -auto-approve" "Destroying infrastructure"; then
        print_error "Destroy failed in cycle $cycle"
        exit 1
    fi
    
    print_section "Cycle $cycle completed successfully!"
    
    if [ $cycle -eq $max_cycles ]; then
        print_status "All test cycles completed successfully!"
        break
    fi
    
    cycle=$((cycle + 1))
    sleep 2
done

print_status "Test cycle completed without errors"
