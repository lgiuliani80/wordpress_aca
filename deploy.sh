#!/bin/bash
# WordPress on Azure Container Apps - Deployment Script
# This script automates the deployment of WordPress infrastructure

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

print_info "Azure CLI is installed"

# Check if user is logged in
if ! az account show &> /dev/null; then
    print_warning "Not logged in to Azure. Initiating login..."
    az login
fi

print_info "Azure CLI authentication verified"

# Get user inputs
read -p "Enter Resource Group Name (default: rg-wordpress-aca): " RESOURCE_GROUP
RESOURCE_GROUP=${RESOURCE_GROUP:-rg-wordpress-aca}

read -p "Enter Location (default: westeurope): " LOCATION
LOCATION=${LOCATION:-westeurope}

read -p "Enter Environment Name (default: wordpress-prod): " ENV_NAME
ENV_NAME=${ENV_NAME:-wordpress-prod}

read -p "Enter MySQL Admin Username (default: mysqladmin): " MYSQL_USER
MYSQL_USER=${MYSQL_USER:-mysqladmin}

read -s -p "Enter MySQL Admin Password (min 8 chars, must have upper, lower, number, special): " MYSQL_PASSWORD
echo

# Validate MySQL password complexity
if [ ${#MYSQL_PASSWORD} -lt 8 ]; then
    print_error "MySQL password must be at least 8 characters long"
    exit 1
fi

if ! [[ "$MYSQL_PASSWORD" =~ [A-Z] ]]; then
    print_error "MySQL password must contain at least one uppercase letter"
    exit 1
fi

if ! [[ "$MYSQL_PASSWORD" =~ [a-z] ]]; then
    print_error "MySQL password must contain at least one lowercase letter"
    exit 1
fi

if ! [[ "$MYSQL_PASSWORD" =~ [0-9] ]]; then
    print_error "MySQL password must contain at least one number"
    exit 1
fi

if ! [[ "$MYSQL_PASSWORD" =~ [^a-zA-Z0-9] ]]; then
    print_error "MySQL password must contain at least one special character"
    exit 1
fi

# Create resource group
print_info "Creating resource group: $RESOURCE_GROUP in $LOCATION..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output table

# Deploy Bicep template
print_info "Starting Bicep deployment..."
print_warning "This may take 15-20 minutes. Please be patient..."

DEPLOYMENT_OUTPUT=$(az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file main.bicep \
    --parameters environmentName="$ENV_NAME" \
    --parameters location="$LOCATION" \
    --parameters mysqlAdminUser="$MYSQL_USER" \
    --parameters mysqlAdminPassword="$MYSQL_PASSWORD" \
    --output json)

if [ $? -eq 0 ]; then
    print_info "Deployment completed successfully!"
    
    # Extract outputs
    WORDPRESS_URL=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.wordpressUrl.value')
    STORAGE_NAME=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.storageAccountName.value')
    MYSQL_FQDN=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.mysqlServerFqdn.value')
    
    echo ""
    print_info "=========================================="
    print_info "WordPress Deployment Information"
    print_info "=========================================="
    print_info "WordPress URL: $WORDPRESS_URL"
    print_info "Storage Account: $STORAGE_NAME"
    print_info "MySQL Server: $MYSQL_FQDN"
    print_info "=========================================="
    echo ""
    print_info "Next steps:"
    echo "1. Navigate to $WORDPRESS_URL"
    echo "2. Complete WordPress installation wizard"
    echo "3. Create your admin user and password"
    echo ""
else
    print_error "Deployment failed. Please check the error messages above."
    exit 1
fi
