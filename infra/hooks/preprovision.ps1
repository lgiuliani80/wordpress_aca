# Pre-provision hook for WordPress on Azure Container Apps
# This script validates all input parameters before infrastructure deployment

# Exit on error
$ErrorActionPreference = "Stop"

# Color output functions
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-CustomWarning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-CustomError {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

Write-Info "Running pre-provision validation..."

# Get environment variables from azd
try {
    $azdEnvValues = azd env get-values 2>$null
    $AZURE_ENV_NAME = $null
    $MYSQL_ADMIN_USER = $null
    $MYSQL_ADMIN_PASSWORD = $null
    $SITE_NAME = $null
    
    foreach ($line in $azdEnvValues) {
        if ($line -match '^AZURE_ENV_NAME=(.+)$') {
            $AZURE_ENV_NAME = $matches[1].Trim('"')
        }
        if ($line -match '^MYSQL_ADMIN_USER=(.+)$') {
            $MYSQL_ADMIN_USER = $matches[1].Trim('"')
        }
        if ($line -match '^MYSQL_ADMIN_PASSWORD=(.+)$') {
            $MYSQL_ADMIN_PASSWORD = $matches[1].Trim('"')
        }
        if ($line -match '^SITE_NAME=(.+)$') {
            $SITE_NAME = $matches[1].Trim('"')
        }
    }
} catch {
    Write-CustomError "Failed to retrieve azd environment values"
    exit 1
}

# Set defaults if not provided
if ([string]::IsNullOrWhiteSpace($MYSQL_ADMIN_USER)) {
    $MYSQL_ADMIN_USER = "mysqladmin"
}

if ([string]::IsNullOrWhiteSpace($SITE_NAME)) {
    $SITE_NAME = "wpsite"
}

Write-Info "Validating parameters..."
Write-Info "Environment Name: $AZURE_ENV_NAME"
Write-Info "MySQL Admin User: $MYSQL_ADMIN_USER"
Write-Info "Site Name: $SITE_NAME"

# Validate environment name for storage account compatibility
# Storage account name will be: st${environmentName}${uniqueSuffix}
# uniqueString generates ~13 chars, so we need environmentName to be max 9 chars (st=2 + env=9 + unique=13 = 24)
if ([string]::IsNullOrWhiteSpace($AZURE_ENV_NAME)) {
    Write-CustomError "AZURE_ENV_NAME is not set. Please run 'azd init' first."
    exit 1
}

if ($AZURE_ENV_NAME.Length -lt 1 -or $AZURE_ENV_NAME.Length -gt 9) {
    Write-CustomError "Environment name must be between 1 and 9 characters to ensure storage account name stays within 24 character limit"
    Write-CustomError "Current length: $($AZURE_ENV_NAME.Length)"
    exit 1
}

if ($AZURE_ENV_NAME -notmatch '^[a-z0-9]+$') {
    Write-CustomError "Environment name can only contain lowercase letters and numbers (no hyphens, underscores, or special characters)"
    Write-CustomError "This is required for storage account naming which only allows lowercase letters and numbers"
    Write-CustomError "Current value: $AZURE_ENV_NAME"
    exit 1
}

# Validate resulting resource names won't exceed Azure limits
# All validations account for prefixes/suffixes added in Bicep template
# uniqueString() generates approximately 13 characters

# Storage Account: st${environmentName}${uniqueSuffix} (max 24 chars)
# Already validated above: 2 + $AZURE_ENV_NAME.Length + 13 <= 24, so $AZURE_ENV_NAME.Length <= 9

# MySQL Server: mysql-${environmentName}-${uniqueSuffix} (max 63 chars)
# Formula: 6 + $AZURE_ENV_NAME.Length + 1 + 13 <= 63, so $AZURE_ENV_NAME.Length <= 43
$MYSQL_PROJECTED_LENGTH = 6 + $AZURE_ENV_NAME.Length + 1 + 13
if ($MYSQL_PROJECTED_LENGTH -gt 63) {
    Write-CustomError "Environment name too long: MySQL server name would be $MYSQL_PROJECTED_LENGTH chars, exceeding 63 character limit"
    Write-CustomError "Projected name: mysql-$AZURE_ENV_NAME-<13-char-suffix>"
    exit 1
}

# Redis Cache: redis-${environmentName}-${uniqueSuffix} (max 63 chars)
# Formula: 6 + $AZURE_ENV_NAME.Length + 1 + 13 <= 63, so $AZURE_ENV_NAME.Length <= 43
$REDIS_PROJECTED_LENGTH = 6 + $AZURE_ENV_NAME.Length + 1 + 13
if ($REDIS_PROJECTED_LENGTH -gt 63) {
    Write-CustomError "Environment name too long: Redis cache name would be $REDIS_PROJECTED_LENGTH chars, exceeding 63 character limit"
    Write-CustomError "Projected name: redis-$AZURE_ENV_NAME-<13-char-suffix>"
    exit 1
}

# VNet: vnet-${environmentName} (max 64 chars)
# Formula: 5 + $AZURE_ENV_NAME.Length <= 64, so $AZURE_ENV_NAME.Length <= 59
$VNET_PROJECTED_LENGTH = 5 + $AZURE_ENV_NAME.Length
if ($VNET_PROJECTED_LENGTH -gt 64) {
    Write-CustomError "Environment name too long: VNet name would be $VNET_PROJECTED_LENGTH chars, exceeding 64 character limit"
    Write-CustomError "Projected name: vnet-$AZURE_ENV_NAME"
    exit 1
}

# Container App Environment: cae-${environmentName} (max 32 chars)
# Formula: 4 + $AZURE_ENV_NAME.Length <= 32, so $AZURE_ENV_NAME.Length <= 28
$CAE_PROJECTED_LENGTH = 4 + $AZURE_ENV_NAME.Length
if ($CAE_PROJECTED_LENGTH -gt 32) {
    Write-CustomError "Environment name too long: Container App Environment name would be $CAE_PROJECTED_LENGTH chars, exceeding 32 character limit"
    Write-CustomError "Projected name: cae-$AZURE_ENV_NAME"
    exit 1
}

# Container App: ca-${sitename}-${environmentName} (max 32 chars)
# Formula: 3 + $SITE_NAME.Length + 1 + $AZURE_ENV_NAME.Length <= 32
$SITENAME_LENGTH = $SITE_NAME.Length
$CA_PROJECTED_LENGTH = 3 + $SITENAME_LENGTH + 1 + $AZURE_ENV_NAME.Length
if ($CA_PROJECTED_LENGTH -gt 32) {
    Write-CustomError "Container App name would be $CA_PROJECTED_LENGTH chars, exceeding 32 character limit"
    Write-CustomError "Projected name: ca-$SITE_NAME-$AZURE_ENV_NAME"
    Write-CustomError "Consider using a shorter site name or environment name"
    exit 1
}

# Validate MySQL username (alphanumeric only, no special characters)
if (-not [string]::IsNullOrWhiteSpace($MYSQL_ADMIN_USER)) {
    if ($MYSQL_ADMIN_USER -notmatch '^[a-zA-Z0-9]+$') {
        Write-CustomError "MySQL username can only contain alphanumeric characters (no special characters or spaces)"
        Write-CustomError "Current value: $MYSQL_ADMIN_USER"
        exit 1
    }
    if ($MYSQL_ADMIN_USER.Length -lt 1 -or $MYSQL_ADMIN_USER.Length -gt 16) {
        Write-CustomError "MySQL username must be between 1 and 16 characters"
        Write-CustomError "Current length: $($MYSQL_ADMIN_USER.Length)"
        exit 1
    }
}

# Validate MySQL password complexity
if ([string]::IsNullOrWhiteSpace($MYSQL_ADMIN_PASSWORD)) {
    Write-CustomError "MYSQL_ADMIN_PASSWORD is not set"
    Write-CustomError "Please set it with: azd env set MYSQL_ADMIN_PASSWORD '<your-password>'"
    exit 1
}

if ($MYSQL_ADMIN_PASSWORD.Length -lt 8) {
    Write-CustomError "MySQL password must be at least 8 characters long"
    Write-CustomError "Current length: $($MYSQL_ADMIN_PASSWORD.Length)"
    exit 1
}

if ($MYSQL_ADMIN_PASSWORD -notmatch '[A-Z]') {
    Write-CustomError "MySQL password must contain at least one uppercase letter"
    exit 1
}

if ($MYSQL_ADMIN_PASSWORD -notmatch '[a-z]') {
    Write-CustomError "MySQL password must contain at least one lowercase letter"
    exit 1
}

if ($MYSQL_ADMIN_PASSWORD -notmatch '[0-9]') {
    Write-CustomError "MySQL password must contain at least one number"
    exit 1
}

if ($MYSQL_ADMIN_PASSWORD -notmatch '[^a-zA-Z0-9]') {
    Write-CustomError "MySQL password must contain at least one special character"
    exit 1
}

Write-Info "All parameter validations passed successfully!"
Write-Info "Environment name: $AZURE_ENV_NAME (length: $($AZURE_ENV_NAME.Length))"
Write-Info "MySQL admin user: $MYSQL_ADMIN_USER (length: $($MYSQL_ADMIN_USER.Length))"
Write-Info "Site name: $SITE_NAME (length: $($SITE_NAME.Length))"
Write-Info "Projected resource name lengths:"
Write-Info "  - Storage Account: $(2 + $AZURE_ENV_NAME.Length + 13) chars (max 24)"
Write-Info "  - MySQL Server: $MYSQL_PROJECTED_LENGTH chars (max 63)"
Write-Info "  - Redis Cache: $REDIS_PROJECTED_LENGTH chars (max 63)"
Write-Info "  - VNet: $VNET_PROJECTED_LENGTH chars (max 64)"
Write-Info "  - Container App Environment: $CAE_PROJECTED_LENGTH chars (max 32)"
Write-Info "  - Container App: $CA_PROJECTED_LENGTH chars (max 32)"

Write-Info "Pre-provision validation completed successfully!"
