# WordPress on Azure Container Apps - Deployment Script (PowerShell)
# This script automates the deployment of WordPress infrastructure

# Enable strict error handling
$ErrorActionPreference = "Stop"

# Function to print colored messages
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Check if Azure CLI is installed
try {
    $azVersion = az version 2>$null
    if (-not $azVersion) {
        throw "Azure CLI not found"
    }
    Write-Info "Azure CLI is installed"
}
catch {
    Write-Error-Custom "Azure CLI is not installed. Please install it first."
    exit 1
}

# Check if user is logged in
try {
    $accountInfo = az account show 2>$null
    if (-not $accountInfo) {
        throw "Not logged in"
    }
    Write-Info "Azure CLI authentication verified"
}
catch {
    Write-Warning-Custom "Not logged in to Azure. Initiating login..."
    az login
}

# Get user inputs with defaults
$RESOURCE_GROUP = Read-Host "Enter Resource Group Name (default: rg-wordpress-aca)"
if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    $RESOURCE_GROUP = "rg-wordpress-aca"
}

# Validate resource group name (1-90 chars, alphanumeric, -, _, ., ())
if ($RESOURCE_GROUP.Length -lt 1 -or $RESOURCE_GROUP.Length -gt 90) {
    Write-Error-Custom "Resource group name must be between 1 and 90 characters"
    exit 1
}
if ($RESOURCE_GROUP -notmatch '^[a-zA-Z0-9._()-]+$') {
    Write-Error-Custom "Resource group name can only contain alphanumeric characters, periods, underscores, hyphens, and parentheses"
    exit 1
}

$LOCATION = Read-Host "Enter Location (default: westeurope)"
if ([string]::IsNullOrWhiteSpace($LOCATION)) {
    $LOCATION = "westeurope"
}

$ENV_NAME = Read-Host "Enter Environment Name (default: wprod)"
if ([string]::IsNullOrWhiteSpace($ENV_NAME)) {
    $ENV_NAME = "wprod"
}

# Validate environment name for storage account compatibility
# Storage account name will be: st${environmentName}${uniqueSuffix}
# uniqueString generates ~13 chars, so we need environmentName to be max 9 chars (st=2 + env=9 + unique=13 = 24)
if ($ENV_NAME.Length -lt 1 -or $ENV_NAME.Length -gt 9) {
    Write-Error-Custom "Environment name must be between 1 and 9 characters to ensure storage account name stays within 24 character limit"
    exit 1
}
if ($ENV_NAME -notmatch '^[a-z0-9]+$') {
    Write-Error-Custom "Environment name can only contain lowercase letters and numbers (no hyphens, underscores, or special characters)"
    Write-Error-Custom "This is required for storage account naming which only allows lowercase letters and numbers"
    exit 1
}

# Validate resulting resource names won't exceed Azure limits
# All validations account for prefixes/suffixes added in Bicep template
# uniqueString() generates approximately 13 characters

# Storage Account: st${environmentName}${uniqueSuffix} (max 24 chars)
# Already validated above: 2 + $ENV_NAME.Length + 13 <= 24, so $ENV_NAME.Length <= 9

# MySQL Server: mysql-${environmentName}-${uniqueSuffix} (max 63 chars)
# Formula: 6 + $ENV_NAME.Length + 1 + 13 <= 63, so $ENV_NAME.Length <= 43
$MYSQL_PROJECTED_LENGTH = 6 + $ENV_NAME.Length + 1 + 13
if ($MYSQL_PROJECTED_LENGTH -gt 63) {
    Write-Error-Custom "Environment name too long: MySQL server name would be $MYSQL_PROJECTED_LENGTH chars, exceeding 63 character limit"
    Write-Error-Custom "Projected name: mysql-$ENV_NAME-<13-char-suffix>"
    exit 1
}

# Redis Cache: redis-${environmentName}-${uniqueSuffix} (max 63 chars)
# Formula: 6 + $ENV_NAME.Length + 1 + 13 <= 63, so $ENV_NAME.Length <= 43
$REDIS_PROJECTED_LENGTH = 6 + $ENV_NAME.Length + 1 + 13
if ($REDIS_PROJECTED_LENGTH -gt 63) {
    Write-Error-Custom "Environment name too long: Redis cache name would be $REDIS_PROJECTED_LENGTH chars, exceeding 63 character limit"
    Write-Error-Custom "Projected name: redis-$ENV_NAME-<13-char-suffix>"
    exit 1
}

# VNet: vnet-${environmentName} (max 64 chars)
# Formula: 5 + $ENV_NAME.Length <= 64, so $ENV_NAME.Length <= 59
$VNET_PROJECTED_LENGTH = 5 + $ENV_NAME.Length
if ($VNET_PROJECTED_LENGTH -gt 64) {
    Write-Error-Custom "Environment name too long: VNet name would be $VNET_PROJECTED_LENGTH chars, exceeding 64 character limit"
    Write-Error-Custom "Projected name: vnet-$ENV_NAME"
    exit 1
}

# Container App Environment: cae-${environmentName} (max 32 chars)
# Formula: 4 + $ENV_NAME.Length <= 32, so $ENV_NAME.Length <= 28
$CAE_PROJECTED_LENGTH = 4 + $ENV_NAME.Length
if ($CAE_PROJECTED_LENGTH -gt 32) {
    Write-Error-Custom "Environment name too long: Container App Environment name would be $CAE_PROJECTED_LENGTH chars, exceeding 32 character limit"
    Write-Error-Custom "Projected name: cae-$ENV_NAME"
    exit 1
}

# Container App: ca-${sitename}-${environmentName} (max 32 chars)
# Default sitename is 'wpsite' (6 chars), but could be changed in Bicep
# Formula: 3 + 6 + 1 + $ENV_NAME.Length <= 32, so $ENV_NAME.Length <= 22 (with default sitename)
# Using default sitename for validation
$SITENAME_LENGTH = 6  # default 'wpsite'
$CA_PROJECTED_LENGTH = 3 + $SITENAME_LENGTH + 1 + $ENV_NAME.Length
if ($CA_PROJECTED_LENGTH -gt 32) {
    Write-Error-Custom "Environment name too long: Container App name would be $CA_PROJECTED_LENGTH chars, exceeding 32 character limit"
    Write-Error-Custom "Projected name: ca-wpsite-$ENV_NAME (assuming default sitename 'wpsite')"
    exit 1
}

$MYSQL_USER = Read-Host "Enter MySQL Admin Username (default: mysqladmin)"
if ([string]::IsNullOrWhiteSpace($MYSQL_USER)) {
    $MYSQL_USER = "mysqladmin"
}

# Validate MySQL username (alphanumeric only, no special characters)
if ($MYSQL_USER -notmatch '^[a-zA-Z0-9]+$') {
    Write-Error-Custom "MySQL username can only contain alphanumeric characters (no special characters or spaces)"
    exit 1
}
if ($MYSQL_USER.Length -lt 1 -or $MYSQL_USER.Length -gt 16) {
    Write-Error-Custom "MySQL username must be between 1 and 16 characters"
    exit 1
}

$MYSQL_PASSWORD = Read-Host "Enter MySQL Admin Password (min 8 chars, must have upper, lower, number, special)" -AsSecureString
$MYSQL_PASSWORD_PLAIN = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($MYSQL_PASSWORD)
)

# Validate MySQL password complexity
if ($MYSQL_PASSWORD_PLAIN.Length -lt 8) {
    Write-Error-Custom "MySQL password must be at least 8 characters long"
    exit 1
}

if ($MYSQL_PASSWORD_PLAIN -notmatch '[A-Z]') {
    Write-Error-Custom "MySQL password must contain at least one uppercase letter"
    exit 1
}

if ($MYSQL_PASSWORD_PLAIN -notmatch '[a-z]') {
    Write-Error-Custom "MySQL password must contain at least one lowercase letter"
    exit 1
}

if ($MYSQL_PASSWORD_PLAIN -notmatch '[0-9]') {
    Write-Error-Custom "MySQL password must contain at least one number"
    exit 1
}

if ($MYSQL_PASSWORD_PLAIN -notmatch '[^a-zA-Z0-9]') {
    Write-Error-Custom "MySQL password must contain at least one special character"
    exit 1
}

# Get current public IP address
Write-Info "Retrieving current public IP address from ipify.org..."
try {
    $CURRENT_IP = (Invoke-RestMethod -Uri "https://api.ipify.org?format=text" -TimeoutSec 10).Trim()
    Write-Info "Current public IP: $CURRENT_IP"
}
catch {
    Write-Warning-Custom "Could not retrieve public IP. Deployment will proceed without IP restriction."
    $CURRENT_IP = ""
}

# Create resource group
Write-Info "Creating resource group: $RESOURCE_GROUP in $LOCATION..."
az group create --name $RESOURCE_GROUP --location $LOCATION --output table

# Deploy Bicep template
Write-Info "Starting Bicep deployment..."
Write-Warning-Custom "This may take 15-20 minutes. Please be patient..."

#az deployment group create `
#    --resource-group $RESOURCE_GROUP `
#    --template-file main.bicep `
#    --parameters environmentName=$ENV_NAME `
#    --parameters location=$LOCATION `
#    --parameters mysqlAdminUser=$MYSQL_USER `
#    --parameters mysqlAdminPassword=$MYSQL_PASSWORD_PLAIN `
#    --parameters allowedIpAddress=$CURRENT_IP --debug

$deploymentOutput = az deployment group create `
    --resource-group $RESOURCE_GROUP `
    --template-file main.bicep `
    --parameters environmentName=$ENV_NAME `
    --parameters location=$LOCATION `
    --parameters mysqlAdminUser=$MYSQL_USER `
    --parameters mysqlAdminPassword=$MYSQL_PASSWORD_PLAIN `
    --parameters allowedIpAddress=$CURRENT_IP `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -eq 0) {
    Write-Info "Deployment completed successfully!"
    
    # Extract outputs
    $WORDPRESS_URL = $deploymentOutput.properties.outputs.wordpressUrl.value
    $STORAGE_NAME = $deploymentOutput.properties.outputs.storageAccountName.value
    $MYSQL_FQDN = $deploymentOutput.properties.outputs.mysqlServerFqdn.value
    
    # Upload nginx.conf to NFS share
    Write-Info "Uploading nginx.conf to NFS share..."
    
    # Get storage account key
    $STORAGE_KEY = az storage account keys list `
        --resource-group $RESOURCE_GROUP `
        --account-name $STORAGE_NAME `
        --query "[0].value" -o tsv
    
    if (Test-Path "nginx.conf") {
        # Upload nginx.conf to the nginx-config NFS share
        az storage file upload `
            --account-name $STORAGE_NAME `
            --account-key $STORAGE_KEY `
            --share-name "nginx-config" `
            --source "nginx.conf" `
            --path "nginx.conf" `
            --output table
        
        if ($LASTEXITCODE -eq 0) {
            Write-Info "nginx.conf uploaded successfully to NFS share"
        }
        else {
            Write-Warning-Custom "Failed to upload nginx.conf. You may need to upload it manually."
        }
    }
    else {
        Write-Warning-Custom "nginx.conf file not found in current directory. Skipping upload."
    }
    
    Write-Host ""
    Write-Info "=========================================="
    Write-Info "WordPress Deployment Information"
    Write-Info "=========================================="
    Write-Info "WordPress URL: $WORDPRESS_URL"
    Write-Info "Storage Account: $STORAGE_NAME"
    Write-Info "MySQL Server: $MYSQL_FQDN"
    Write-Info "=========================================="
    Write-Host ""
    Write-Info "Next steps:"
    Write-Host "1. Navigate to $WORDPRESS_URL"
    Write-Host "2. Complete WordPress installation wizard"
    Write-Host "3. Create your admin user and password"
    Write-Host "4. The nginx.conf has been uploaded to the NFS share"
    Write-Host ""
}
else {
    Write-Error-Custom "Deployment failed. Please check the error messages above."
    exit 1
}
