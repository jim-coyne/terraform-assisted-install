#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Terraform Assisted Install Deployment${NC}"

# Function to print colored messages
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed. Please install Terraform first."
    exit 1
fi

# Check if required variables file exists
if [ ! -f "terraform.tfvars" ]; then
    if [ -f "terraform.tfvars.example" ]; then
        print_warning "terraform.tfvars not found. Copying from example..."
        cp terraform.tfvars.example terraform.tfvars
        print_warning "Please edit terraform.tfvars with your specific values before continuing."
        exit 1
    else
        print_error "terraform.tfvars not found and no example available."
        exit 1
    fi
fi

# Initialize Terraform
print_status "Initializing Terraform..."
if ! terraform init; then
    print_error "Terraform initialization failed"
    exit 1
fi

# Validate configuration
print_status "Validating Terraform configuration..."
if ! terraform validate; then
    print_error "Terraform validation failed"
    exit 1
fi

# Format code
print_status "Formatting Terraform code..."
terraform fmt -recursive

# Plan deployment
print_status "Creating Terraform plan..."
if ! terraform plan -out=tfplan; then
    print_error "Terraform planning failed"
    exit 1
fi

# Ask for confirmation
echo
read -p "Do you want to apply this plan? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Deployment cancelled by user"
    exit 0
fi

# Apply configuration
print_status "Applying Terraform configuration..."
if terraform apply tfplan; then
    print_status "Deployment completed successfully!"
    
    # Display outputs
    echo
    print_status "Deployment outputs:"
    terraform output
    
    # Clean up plan file
    rm -f tfplan
else
    print_error "Terraform apply failed"
    exit 1
fi

print_status "Deployment script completed"
