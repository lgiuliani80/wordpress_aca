#!/bin/bash
# Pre-provision hook for WordPress on Azure Container Apps
# This script validates all input parameters before infrastructure deployment

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

print_info "Running pre-provision validation..."

# Get environment variables from azd
AZURE_ENV_NAME=$(azd env get-values | grep AZURE_ENV_NAME | cut -d'=' -f2 | tr -d '"')
MYSQL_ADMIN_USER=$(azd env get-values | grep MYSQL_ADMIN_USER | cut -d'=' -f2 | tr -d '"')
MYSQL_ADMIN_PASSWORD=$(azd env get-values | grep MYSQL_ADMIN_PASSWORD | cut -d'=' -f2 | tr -d '"')
SITE_NAME=$(azd env get-values | grep SITE_NAME | cut -d'=' -f2 | tr -d '"')

# Set defaults if not provided
MYSQL_ADMIN_USER=${MYSQL_ADMIN_USER:-mysqladmin}
SITE_NAME=${SITE_NAME:-wpsite}

print_info "Validating parameters..."
print_info "Environment Name: $AZURE_ENV_NAME"
print_info "MySQL Admin User: $MYSQL_ADMIN_USER"
print_info "Site Name: $SITE_NAME"

# Validate environment name for storage account compatibility
# Storage account name will be: st${environmentName}${uniqueSuffix}
# uniqueString generates ~13 chars, so we need environmentName to be max 9 chars (st=2 + env=9 + unique=13 = 24)
if [ -z "$AZURE_ENV_NAME" ]; then
    print_error "AZURE_ENV_NAME is not set. Please run 'azd init' first."
    exit 1
fi

if [ ${#AZURE_ENV_NAME} -lt 1 ] || [ ${#AZURE_ENV_NAME} -gt 9 ]; then
    print_error "Environment name must be between 1 and 9 characters to ensure storage account name stays within 24 character limit"
    print_error "Current length: ${#AZURE_ENV_NAME}"
    exit 1
fi

if ! [[ "$AZURE_ENV_NAME" =~ ^[a-z0-9]+$ ]]; then
    print_error "Environment name can only contain lowercase letters and numbers (no hyphens, underscores, or special characters)"
    print_error "This is required for storage account naming which only allows lowercase letters and numbers"
    print_error "Current value: $AZURE_ENV_NAME"
    exit 1
fi

# Validate resulting resource names won't exceed Azure limits
# All validations account for prefixes/suffixes added in Bicep template
# uniqueString() generates approximately 13 characters

# Storage Account: st${environmentName}${uniqueSuffix} (max 24 chars)
# Already validated above: 2 + ${#AZURE_ENV_NAME} + 13 <= 24, so ${#AZURE_ENV_NAME} <= 9

# MySQL Server: mysql-${environmentName}-${uniqueSuffix} (max 63 chars)
# Formula: 6 + ${#AZURE_ENV_NAME} + 1 + 13 <= 63, so ${#AZURE_ENV_NAME} <= 43
MYSQL_PROJECTED_LENGTH=$((6 + ${#AZURE_ENV_NAME} + 1 + 13))
if [ $MYSQL_PROJECTED_LENGTH -gt 63 ]; then
    print_error "Environment name too long: MySQL server name would be $MYSQL_PROJECTED_LENGTH chars, exceeding 63 character limit"
    print_error "Projected name: mysql-${AZURE_ENV_NAME}-<13-char-suffix>"
    exit 1
fi

# Redis Cache: redis-${environmentName}-${uniqueSuffix} (max 63 chars)
# Formula: 6 + ${#AZURE_ENV_NAME} + 1 + 13 <= 63, so ${#AZURE_ENV_NAME} <= 43
REDIS_PROJECTED_LENGTH=$((6 + ${#AZURE_ENV_NAME} + 1 + 13))
if [ $REDIS_PROJECTED_LENGTH -gt 63 ]; then
    print_error "Environment name too long: Redis cache name would be $REDIS_PROJECTED_LENGTH chars, exceeding 63 character limit"
    print_error "Projected name: redis-${AZURE_ENV_NAME}-<13-char-suffix>"
    exit 1
fi

# VNet: vnet-${environmentName} (max 64 chars)
# Formula: 5 + ${#AZURE_ENV_NAME} <= 64, so ${#AZURE_ENV_NAME} <= 59
VNET_PROJECTED_LENGTH=$((5 + ${#AZURE_ENV_NAME}))
if [ $VNET_PROJECTED_LENGTH -gt 64 ]; then
    print_error "Environment name too long: VNet name would be $VNET_PROJECTED_LENGTH chars, exceeding 64 character limit"
    print_error "Projected name: vnet-${AZURE_ENV_NAME}"
    exit 1
fi

# Container App Environment: cae-${environmentName} (max 32 chars)
# Formula: 4 + ${#AZURE_ENV_NAME} <= 32, so ${#AZURE_ENV_NAME} <= 28
CAE_PROJECTED_LENGTH=$((4 + ${#AZURE_ENV_NAME}))
if [ $CAE_PROJECTED_LENGTH -gt 32 ]; then
    print_error "Environment name too long: Container App Environment name would be $CAE_PROJECTED_LENGTH chars, exceeding 32 character limit"
    print_error "Projected name: cae-${AZURE_ENV_NAME}"
    exit 1
fi

# Container App: ca-${sitename}-${environmentName} (max 32 chars)
# Formula: 3 + ${#SITE_NAME} + 1 + ${#AZURE_ENV_NAME} <= 32
SITENAME_LENGTH=${#SITE_NAME}
CA_PROJECTED_LENGTH=$((3 + SITENAME_LENGTH + 1 + ${#AZURE_ENV_NAME}))
if [ $CA_PROJECTED_LENGTH -gt 32 ]; then
    print_error "Container App name would be $CA_PROJECTED_LENGTH chars, exceeding 32 character limit"
    print_error "Projected name: ca-${SITE_NAME}-${AZURE_ENV_NAME}"
    print_error "Consider using a shorter site name or environment name"
    exit 1
fi

# Validate MySQL username (alphanumeric only, no special characters)
if [ -n "$MYSQL_ADMIN_USER" ]; then
    if ! [[ "$MYSQL_ADMIN_USER" =~ ^[a-zA-Z0-9]+$ ]]; then
        print_error "MySQL username can only contain alphanumeric characters (no special characters or spaces)"
        print_error "Current value: $MYSQL_ADMIN_USER"
        exit 1
    fi
    if [ ${#MYSQL_ADMIN_USER} -lt 1 ] || [ ${#MYSQL_ADMIN_USER} -gt 16 ]; then
        print_error "MySQL username must be between 1 and 16 characters"
        print_error "Current length: ${#MYSQL_ADMIN_USER}"
        exit 1
    fi
fi

# Validate MySQL password complexity
if [ -z "$MYSQL_ADMIN_PASSWORD" ]; then
    print_error "MYSQL_ADMIN_PASSWORD is not set"
    print_error "Please set it with: azd env set MYSQL_ADMIN_PASSWORD '<your-password>'"
    exit 1
fi

if [ ${#MYSQL_ADMIN_PASSWORD} -lt 8 ]; then
    print_error "MySQL password must be at least 8 characters long"
    print_error "Current length: ${#MYSQL_ADMIN_PASSWORD}"
    exit 1
fi

if ! [[ "$MYSQL_ADMIN_PASSWORD" =~ [A-Z] ]]; then
    print_error "MySQL password must contain at least one uppercase letter"
    exit 1
fi

if ! [[ "$MYSQL_ADMIN_PASSWORD" =~ [a-z] ]]; then
    print_error "MySQL password must contain at least one lowercase letter"
    exit 1
fi

if ! [[ "$MYSQL_ADMIN_PASSWORD" =~ [0-9] ]]; then
    print_error "MySQL password must contain at least one number"
    exit 1
fi

if ! [[ "$MYSQL_ADMIN_PASSWORD" =~ [^a-zA-Z0-9] ]]; then
    print_error "MySQL password must contain at least one special character"
    exit 1
fi

print_info "All parameter validations passed successfully!"
print_info "Environment name: $AZURE_ENV_NAME (length: ${#AZURE_ENV_NAME})"
print_info "MySQL admin user: $MYSQL_ADMIN_USER (length: ${#MYSQL_ADMIN_USER})"
print_info "Site name: $SITE_NAME (length: ${#SITE_NAME})"
print_info "Projected resource name lengths:"
print_info "  - Storage Account: $((2 + ${#AZURE_ENV_NAME} + 13)) chars (max 24)"
print_info "  - MySQL Server: $MYSQL_PROJECTED_LENGTH chars (max 63)"
print_info "  - Redis Cache: $REDIS_PROJECTED_LENGTH chars (max 63)"
print_info "  - VNet: $VNET_PROJECTED_LENGTH chars (max 64)"
print_info "  - Container App Environment: $CAE_PROJECTED_LENGTH chars (max 32)"
print_info "  - Container App: $CA_PROJECTED_LENGTH chars (max 32)"

print_info "Pre-provision validation completed successfully!"
