#!/bin/bash

# OCM Authentication - Browser OAuth Flow
# This script uses the same authentication method as the Python version

set -e

echo "🔐 Red Hat OpenShift Authentication"
echo "=================================="
echo ""

# Check if OCM is installed
if ! command -v ocm >/dev/null 2>&1; then
    echo " OCM CLI is not installed."
    echo ""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Installing OCM CLI using Homebrew..."
        if command -v brew >/dev/null 2>&1; then
            brew install ocm
            echo " OCM CLI installed successfully!"
        else
            echo " Homebrew not found. Please install OCM CLI manually:"
            echo "   Download from: https://github.com/openshift-online/ocm-cli/releases"
            exit 1
        fi
    else
        echo "Please install OCM CLI manually:"
        echo "   Download from: https://github.com/openshift-online/ocm-cli/releases"
        exit 1
    fi
    echo ""
fi

# Check current authentication
echo "Checking OCM authentication status..."
if ocm token >/dev/null 2>&1 && [ "$(ocm token)" != "null" ] && [ -n "$(ocm token)" ]; then
    USER_INFO=$(ocm whoami 2>/dev/null)
    if command -v jq >/dev/null 2>&1; then
        USERNAME=$(echo "$USER_INFO" | jq -r '.username // .email // "unknown"')
        echo " Already authenticated as: $USERNAME"
    else
        echo " Already authenticated with OCM"
    fi
    echo ""
    read -p "Continue with current authentication? (y/n): " CONTINUE
    if [ "$CONTINUE" = "y" ] || [ "$CONTINUE" = "Y" ]; then
        echo " Using existing authentication."
        exit 0
    fi
    echo ""
fi

echo " Starting browser-based OAuth authentication..."
echo ""
echo "This will:"
echo "   1. Open your browser to Red Hat SSO"
echo "   2. Complete authentication in the browser"
echo "   3. Automatically return to the terminal"
echo ""
echo "Starting authentication..."

# Use OCM's built-in OAuth flow (same as Python version)
if ocm login --use-auth-code; then
    echo ""
    echo " Authentication successful!"
    
    # Display user info
    USER_INFO=$(ocm whoami 2>/dev/null)
    if [ $? -eq 0 ] && command -v jq >/dev/null 2>&1; then
        USERNAME=$(echo "$USER_INFO" | jq -r '.username // .email // "unknown"')
        ORG=$(echo "$USER_INFO" | jq -r '.organization.name // "unknown"')
        echo "    User: $USERNAME"
        echo "    Organization: $ORG"
    else
        echo "   👤 OCM session active"
    fi
    
    echo ""
    echo "🎉 Ready to deploy OpenShift clusters!"
    echo "   You can now run: terraform plan && terraform apply"
else
    echo " Authentication failed."
    echo ""
    echo "If the browser authentication didn't work, you can try:"
    echo "1. Manual token authentication: ocm login --token=YOUR_TOKEN"
    echo "2. Get token from: https://console.redhat.com/openshift/token"
    exit 1
fi
