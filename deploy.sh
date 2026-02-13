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

# Validate resource group name (1-90 chars, alphanumeric, -, _, ., ())
if [ ${#RESOURCE_GROUP} -lt 1 ] || [ ${#RESOURCE_GROUP} -gt 90 ]; then
    print_error "Resource group name must be between 1 and 90 characters"
    exit 1
fi
if ! [[ "$RESOURCE_GROUP" =~ ^[a-zA-Z0-9._()-]+$ ]]; then
    print_error "Resource group name can only contain alphanumeric characters, periods, underscores, hyphens, and parentheses"
    exit 1
fi

read -p "Enter Location (default: westeurope): " LOCATION
LOCATION=${LOCATION:-westeurope}

read -p "Enter Environment Name (default: wprod): " ENV_NAME
ENV_NAME=${ENV_NAME:-wprod}

# Validate environment name for storage account compatibility
# Storage account name will be: st${environmentName}${uniqueSuffix}
# uniqueString generates ~13 chars, so we need environmentName to be max 9 chars (st=2 + env=9 + unique=13 = 24)
if [ ${#ENV_NAME} -lt 1 ] || [ ${#ENV_NAME} -gt 9 ]; then
    print_error "Environment name must be between 1 and 9 characters to ensure storage account name stays within 24 character limit"
    exit 1
fi
if ! [[ "$ENV_NAME" =~ ^[a-z0-9]+$ ]]; then
    print_error "Environment name can only contain lowercase letters and numbers (no hyphens, underscores, or special characters)"
    print_error "This is required for storage account naming which only allows lowercase letters and numbers"
    exit 1
fi

# Validate resulting resource names won't exceed limits
# MySQL server name: mysql-${environmentName}-${uniqueSuffix} (max 63 chars)
MYSQL_NAME_PREFIX="mysql-${ENV_NAME}-"
if [ ${#MYSQL_NAME_PREFIX} -gt 50 ]; then
    print_error "Environment name too long: MySQL server name would exceed 63 character limit"
    exit 1
fi

# VNet name: vnet-${environmentName} (max 64 chars)
VNET_NAME="vnet-${ENV_NAME}"
if [ ${#VNET_NAME} -gt 64 ]; then
    print_error "Environment name too long: VNet name would exceed 64 character limit"
    exit 1
fi

# Container App Environment: cae-${environmentName} (max 32 chars)
CAE_NAME="cae-${ENV_NAME}"
if [ ${#CAE_NAME} -gt 32 ]; then
    print_error "Environment name too long: Container App Environment name would exceed 32 character limit"
    exit 1
fi

# Container App: ca-wordpress-${environmentName} (max 32 chars)
CA_NAME="ca-wordpress-${ENV_NAME}"
if [ ${#CA_NAME} -gt 32 ]; then
    print_error "Environment name too long: Container App name would exceed 32 character limit"
    exit 1
fi

read -p "Enter MySQL Admin Username (default: mysqladmin): " MYSQL_USER
MYSQL_USER=${MYSQL_USER:-mysqladmin}

# Validate MySQL username (alphanumeric only, no special characters)
if ! [[ "$MYSQL_USER" =~ ^[a-zA-Z0-9]+$ ]]; then
    print_error "MySQL username can only contain alphanumeric characters (no special characters or spaces)"
    exit 1
fi
if [ ${#MYSQL_USER} -lt 1 ] || [ ${#MYSQL_USER} -gt 16 ]; then
    print_error "MySQL username must be between 1 and 16 characters"
    exit 1
fi

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

# Get current public IP address
print_info "Retrieving current public IP address from ipify.org..."
CURRENT_IP=$(curl -s --max-time 10 "https://api.ipify.org?format=text" 2>/dev/null || echo "")
if [ -n "$CURRENT_IP" ]; then
    print_info "Current public IP: $CURRENT_IP"
else
    print_warning "Could not retrieve public IP. Deployment will proceed without IP restriction."
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
    --parameters allowedIpAddress="$CURRENT_IP" \
    --output json)

if [ $? -eq 0 ]; then
    print_info "Deployment completed successfully!"
    
    # Extract outputs
    WORDPRESS_URL=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.wordpressUrl.value')
    STORAGE_NAME=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.storageAccountName.value')
    MYSQL_FQDN=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.mysqlServerFqdn.value')
    
    # Upload nginx.conf to NFS share
    print_info "Uploading nginx.conf to NFS share..."
    
    # Get storage account key
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_NAME" \
        --query "[0].value" -o tsv)
    
    if [ -f "nginx.conf" ]; then
        # Upload nginx.conf to the nginx-config NFS share
        az storage file upload \
            --account-name "$STORAGE_NAME" \
            --account-key "$STORAGE_KEY" \
            --share-name "nginx-config" \
            --source "nginx.conf" \
            --path "nginx.conf" \
            --output table
        
        if [ $? -eq 0 ]; then
            print_info "nginx.conf uploaded successfully to NFS share"
        else
            print_warning "Failed to upload nginx.conf. You may need to upload it manually."
        fi
    else
        print_warning "nginx.conf file not found in current directory. Skipping upload."
    fi
    
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
    echo "4. The nginx.conf has been uploaded to the NFS share"
    echo ""
else
    print_error "Deployment failed. Please check the error messages above."
    exit 1
fi
