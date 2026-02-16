# Post-provision hook for WordPress on Azure Container Apps
# This script uploads nginx.conf to the NFS share after infrastructure deployment

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

Write-Info "Running post-provision hook..."

# Check if Azure CLI is installed
try {
    $null = Get-Command az -ErrorAction Stop
    Write-Info "Azure CLI is installed"
} catch {
    Write-CustomError "Azure CLI (az) is not installed"
    Write-CustomError "Please install Azure CLI: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}

# Check if user is logged in to Azure
try {
    $null = az account show 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Not logged in"
    }
    Write-Info "User is logged in to Azure"
} catch {
    Write-CustomError "Not logged in to Azure"
    Write-CustomError "Please run: az login"
    exit 1
}

# Get current subscription ID
try {
    $currentSubscription = az account show --query id -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($currentSubscription)) {
        throw "Could not retrieve current Azure subscription"
    }
    Write-Info "Current Azure subscription: $currentSubscription"
} catch {
    Write-CustomError "Could not retrieve current Azure subscription"
    exit 1
}

# Get azd target subscription from environment
try {
    $azdEnvValues = azd env get-values 2>$null
    $azdSubscription = $null
    
    foreach ($line in $azdEnvValues) {
        if ($line -match '^AZURE_SUBSCRIPTION_ID=(.+)$') {
            $azdSubscription = $matches[1].Trim('"')
            break
        }
    }
    
    # If azd has a specific subscription set, verify it matches
    if ($azdSubscription) {
        if ($currentSubscription -ne $azdSubscription) {
            Write-CustomError "Azure subscription mismatch!"
            Write-CustomError "Current subscription: $currentSubscription"
            Write-CustomError "azd target subscription: $azdSubscription"
            Write-CustomError "Please switch subscription with: az account set --subscription $azdSubscription"
            exit 1
        }
        Write-Info "Azure subscription matches azd target subscription"
    } else {
        Write-CustomWarning "No AZURE_SUBSCRIPTION_ID set in azd environment, using current subscription"
    }
} catch {
    Write-CustomWarning "Could not retrieve azd subscription information"
}

# Get the outputs from the deployment
try {
    $azdEnvValues = azd env get-values 2>$null
    $storageAccountName = $null
    $resourceGroupName = $null
    
    foreach ($line in $azdEnvValues) {
        if ($line -match '^STORAGE_ACCOUNT_NAME=(.+)$') {
            $storageAccountName = $matches[1].Trim('"')
        }
        if ($line -match '^AZURE_RESOURCE_GROUP_NAME=(.+)$') {
            $resourceGroupName = $matches[1].Trim('"')
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($storageAccountName) -or [string]::IsNullOrWhiteSpace($resourceGroupName)) {
        Write-CustomError "Could not retrieve storage account name or resource group name from azd environment"
        Write-CustomError "STORAGE_ACCOUNT_NAME: $storageAccountName"
        Write-CustomError "RESOURCE_GROUP_NAME: $resourceGroupName"
        exit 1
    }
    
    Write-Info "Storage Account: $storageAccountName"
    Write-Info "Resource Group: $resourceGroupName"
} catch {
    Write-CustomError "Failed to retrieve azd environment values"
    exit 1
}

# Get storage account key
Write-Info "Retrieving storage account key..."
try {
    $storageKey = az storage account keys list `
        --resource-group $resourceGroupName `
        --account-name $storageAccountName `
        --query "[0].value" -o tsv 2>$null
    
    if ([string]::IsNullOrWhiteSpace($storageKey)) {
        throw "Could not retrieve storage account key"
    }
} catch {
    Write-CustomError "Could not retrieve storage account key"
    exit 1
}

# Upload nginx.conf to NFS share
$nginxConfPath = Join-Path (Split-Path -Parent $PSScriptRoot) "nginx.conf"

if (Test-Path $nginxConfPath) {
    Write-Info "Uploading nginx.conf to NFS share..."
    
    try {
        az storage file upload `
            --account-name $storageAccountName `
            --account-key $storageKey `
            --share-name "nginx-config" `
            --source $nginxConfPath `
            --path "nginx.conf" `
            --output table
        
        if ($LASTEXITCODE -eq 0) {
            Write-Info "nginx.conf uploaded successfully to NFS share"
        } else {
            throw "Upload failed"
        }
    } catch {
        Write-CustomError "Failed to upload nginx.conf"
        exit 1
    }
} else {
    Write-CustomError "nginx.conf file not found at $nginxConfPath"
    exit 1
}

# Upload custom-php.ini to NFS share
$phpIniPath = Join-Path (Split-Path -Parent $PSScriptRoot) "custom-php.ini"

if (Test-Path $phpIniPath) {
    Write-Info "Uploading custom-php.ini to NFS share..."
    
    try {
        az storage file upload `
            --account-name $storageAccountName `
            --account-key $storageKey `
            --share-name "php-config" `
            --source $phpIniPath `
            --path "custom-php.ini" `
            --output table
        
        if ($LASTEXITCODE -eq 0) {
            Write-Info "custom-php.ini uploaded successfully to NFS share"
        } else {
            throw "Upload failed"
        }
    } catch {
        Write-CustomError "Failed to upload custom-php.ini"
        exit 1
    }
} else {
    Write-CustomError "custom-php.ini file not found at $phpIniPath"
    exit 1
}

Write-Info "Post-provision hook completed successfully!"
