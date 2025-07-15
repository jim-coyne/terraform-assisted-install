#!/bin/bash

# setup-credentials.sh - Setup script for OCM-based Assisted Installer API

set -e

echo "Setting up Terraform Assisted Install with OCM authentication..."

# Check if required tools are installed
command -v curl >/dev/null 2>&1 || { echo "Error: curl is required but not installed." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required but not installed." >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "Error: terraform is required but not installed." >&2; exit 1; }

# Check if OCM is installed
if ! command -v ocm >/dev/null 2>&1; then
    echo "⚠️  OCM CLI not found. Installing OCM..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew >/dev/null 2>&1; then
            brew install ocm
        else
            echo "Please install Homebrew first, then run: brew install ocm"
            echo "Or download OCM from: https://github.com/openshift-online/ocm-cli/releases"
            exit 1
        fi
    else
        echo "Please install OCM CLI from: https://github.com/openshift-online/ocm-cli/releases"
        exit 1
    fi
fi

# Create terraform.tfvars if it doesn't exist
if [ ! -f "terraform.tfvars" ]; then
    echo "Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo "✓ Created terraform.tfvars"
else
    echo "✓ terraform.tfvars already exists"
fi

# Check OCM login status
echo ""
echo "Checking OCM authentication..."
if ocm token >/dev/null 2>&1 && [ "$(ocm token)" != "null" ] && [ -n "$(ocm token)" ]; then
    echo "✅ OCM authentication verified"
    USER_INFO=$(ocm whoami 2>/dev/null)
    if [ $? -eq 0 ] && command -v jq >/dev/null 2>&1; then
        echo "   👤 User: $(echo "$USER_INFO" | jq -r '.username // .email // "unknown"')"
    else
        echo "   👤 OCM session active"
    fi
else
    echo "⚠️  OCM authentication required"
    echo ""
    echo "🌐 Starting browser-based OAuth authentication..."
    echo "   This will open your browser for secure authentication"
    echo ""
    
    # Use OCM's built-in OAuth flow (same as Python version)
    if ocm login --use-auth-code; then
        echo "✅ OCM authentication successful!"
        USER_INFO=$(ocm whoami 2>/dev/null)
        if [ $? -eq 0 ] && command -v jq >/dev/null 2>&1; then
            echo "   👤 User: $(echo "$USER_INFO" | jq -r '.username // .email // "unknown"')"
        else
            echo "   👤 OCM session active"
        fi
    else
        echo "❌ OCM authentication failed."
        echo "Please try running: ./ocm-browser-auth.sh"
        exit 1
    fi
fi

# Update terraform.tfvars to use OCM authentication
if grep -q "YOUR_REDHAT_API_TOKEN_HERE" terraform.tfvars; then
    echo ""
    echo "Updating terraform.tfvars to use OCM authentication..."
    sed -i.backup 's/YOUR_REDHAT_API_TOKEN_HERE/OCM_TOKEN_PLACEHOLDER/g' terraform.tfvars
    echo "✓ Updated terraform.tfvars for OCM authentication"
fi

# Prompt for SSH public key if needed
if grep -q "YOUR_PUBLIC_KEY_HERE" terraform.tfvars; then
    echo ""
    echo "⚠️  You need to update your SSH public key in terraform.tfvars"
    if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
        echo "   Found SSH key at $HOME/.ssh/id_rsa.pub"
        read -p "Use this key? (y/n): " USE_KEY
        if [ "$USE_KEY" = "y" ] || [ "$USE_KEY" = "Y" ]; then
            SSH_KEY=$(cat "$HOME/.ssh/id_rsa.pub")
            # Escape special characters for sed
            SSH_KEY_ESCAPED=$(echo "$SSH_KEY" | sed 's/[[\.*^$()+?{|]/\\&/g')
            sed -i.backup "s|ssh-rsa AAAAB3NzaC1yc2E... YOUR_PUBLIC_KEY_HERE|$SSH_KEY_ESCAPED|g" terraform.tfvars
            echo "✓ Updated SSH public key in terraform.tfvars"
        fi
    else
        echo "   No SSH key found at $HOME/.ssh/id_rsa.pub"
        echo "   Please manually update the ssh_public_key in terraform.tfvars"
    fi
fi

echo ""
echo "✓ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Review and edit terraform.tfvars as needed"
echo "2. Run: terraform init"
echo "3. Run: terraform plan"
echo "4. Run: terraform apply"
echo ""
echo "The configuration will use the actual Red Hat Assisted Installer API."
echo "Monitor progress in the tmp/ directory for API responses."
