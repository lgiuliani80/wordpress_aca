#!/bin/bash
# Post-provision hook for WordPress on Azure Container Apps
# This script uploads nginx.conf to the NFS share after infrastructure deployment

set -e

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info "Running post-provision hook..."

# Get the outputs from the deployment
STORAGE_ACCOUNT_NAME=$(azd env get-values | grep STORAGE_ACCOUNT_NAME | cut -d'=' -f2 | tr -d '"')
RESOURCE_GROUP_NAME=$(azd env get-values | grep AZURE_RESOURCE_GROUP_NAME | cut -d'=' -f2 | tr -d '"')

if [ -z "$STORAGE_ACCOUNT_NAME" ] || [ -z "$RESOURCE_GROUP_NAME" ]; then
    print_error "Could not retrieve storage account name or resource group name from azd environment"
    print_error "STORAGE_ACCOUNT_NAME: $STORAGE_ACCOUNT_NAME"
    print_error "RESOURCE_GROUP_NAME: $RESOURCE_GROUP_NAME"
    exit 1
fi

print_info "Storage Account: $STORAGE_ACCOUNT_NAME"
print_info "Resource Group: $RESOURCE_GROUP_NAME"

# Get storage account key
print_info "Retrieving storage account key..."
STORAGE_KEY=$(az storage account keys list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --query "[0].value" -o tsv)

if [ -z "$STORAGE_KEY" ]; then
    print_error "Could not retrieve storage account key"
    exit 1
fi

# Upload nginx.conf to NFS share
NGINX_CONF_PATH="$(dirname "$0")/../nginx.conf"

if [ -f "$NGINX_CONF_PATH" ]; then
    print_info "Uploading nginx.conf to NFS share..."
    
    az storage file upload \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_KEY" \
        --share-name "nginx-config" \
        --source "$NGINX_CONF_PATH" \
        --path "nginx.conf" \
        --output table
    
    if [ $? -eq 0 ]; then
        print_info "nginx.conf uploaded successfully to NFS share"
    else
        print_error "Failed to upload nginx.conf"
        exit 1
    fi
else
    print_error "nginx.conf file not found at $NGINX_CONF_PATH"
    exit 1
fi

print_info "Post-provision hook completed successfully!"
