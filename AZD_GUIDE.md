# Azure Developer CLI (azd) Deployment Guide

This guide provides detailed information about deploying WordPress on Azure Container Apps using Azure Developer CLI (azd).

## What is Azure Developer CLI?

Azure Developer CLI (azd) is a command-line tool that simplifies the deployment of applications to Azure. It provides:
- Simple commands for deployment (`azd up`)
- Environment management
- Parameter handling via environment variables
- Automated infrastructure provisioning
- Lifecycle hooks for custom deployment logic

## Project Structure

This project is organized to support azd:

```
wordpress_aca/
├── azure.yaml                      # azd configuration file
├── .azure/                         # azd environment data (gitignored)
├── .env.template                   # Environment variables template
├── infra/                          # Infrastructure as Code
│   ├── main.bicep                  # Main Bicep template
│   ├── main.parameters.json        # Parameters with azd variable substitution
│   ├── nginx.conf                  # Nginx configuration
│   └── hooks/
│       ├── postprovision.sh        # Post-provision hook (Bash/Linux/macOS/WSL)
│       └── postprovision.ps1       # Post-provision hook (PowerShell/Windows)
├── deploy.sh                       # Legacy deployment script
├── deploy.ps1                      # Legacy deployment script (PowerShell)
└── README.md                       # Main documentation
```

## Installation

### Install Azure Developer CLI

**macOS/Linux:**
```bash
curl -fsSL https://aka.ms/install-azd.sh | bash
```

**Windows (PowerShell):**
```powershell
powershell -ex AllSigned -c "Invoke-RestMethod 'https://aka.ms/install-azd.ps1' | Invoke-Expression"
```

**Or using package managers:**
```bash
# macOS with Homebrew
brew tap azure/azd && brew install azd

# Windows with winget
winget install microsoft.azd

# Linux (Debian/Ubuntu)
curl -fsSL https://aka.ms/install-azd.sh | bash
```

Verify installation:
```bash
azd version
```

## Quick Start

### 1. Clone and Navigate

```bash
git clone <your-repository-url>
cd wordpress_aca
```

### 2. Login to Azure

```bash
azd auth login
```

This will open a browser for Azure authentication.

### 3. Initialize Environment (First Time)

```bash
azd init
```

You'll be prompted for:
- **Environment Name**: A unique name for your deployment (1-9 chars, lowercase/numbers only)
  - Examples: `wprod`, `wdev`, `wtest`
  - This is stored in `.azure/<env-name>/` directory

### 4. Set Required Parameters

Before deploying, set the MySQL password:

```bash
azd env set MYSQL_ADMIN_PASSWORD 'YourSecurePassword123!'
```

**Optional parameters** (with defaults):
```bash
azd env set MYSQL_ADMIN_USER 'mysqladmin'
azd env set WORDPRESS_DB_NAME 'wordpress'
azd env set SITE_NAME 'wpsite'
azd env set WORDPRESS_IMAGE 'wordpress:php8.2-fpm'
azd env set NGINX_IMAGE 'nginx:alpine'
```

### 5. Deploy Everything

```bash
azd up
```

This single command will:
1. Prompt for Azure subscription and location
2. Create a resource group (named `rg-<env-name>`)
3. Provision all Azure resources
4. Run the postprovision hook to upload nginx.conf
5. Display the WordPress URL and other outputs

## Environment Management

### List Environments

```bash
azd env list
```

### Switch Between Environments

```bash
azd env select <environment-name>
```

### View Environment Variables

```bash
azd env get-values
```

### Set/Update Environment Variables

```bash
# Set a variable
azd env set MYSQL_ADMIN_PASSWORD 'NewPassword123!'

# Remove a variable
azd env set MYSQL_ADMIN_PASSWORD --unset
```

## Deployment Commands

### Full Deployment

Deploy everything (infrastructure + hooks):
```bash
azd up
```

### Infrastructure Only

Provision infrastructure without hooks:
```bash
azd provision
```

### Re-run Hooks

If you need to re-upload nginx.conf or run post-provision tasks:

**Bash (Linux/macOS/WSL):**
```bash
./infra/hooks/postprovision.sh
```

**PowerShell (Windows):**
```powershell
./infra/hooks/postprovision.ps1
```

### Update Infrastructure

After modifying Bicep files:
```bash
azd provision
```

Or deploy everything again:
```bash
azd up
```

### View Deployment Status

```bash
azd show
```

## Clean Up

### Delete All Resources

```bash
azd down
```

This will delete the resource group and all resources. The environment configuration in `.azure/<env-name>/` is preserved.

### Remove Environment Configuration

```bash
azd env remove <environment-name>
```

## Parameter Substitution

The `infra/main.parameters.json` file uses azd variable substitution syntax:

```json
{
  "parameters": {
    "environmentName": {
      "value": "${AZURE_ENV_NAME}"
    },
    "mysqlAdminPassword": {
      "value": "${MYSQL_ADMIN_PASSWORD}"
    },
    "mysqlAdminUser": {
      "value": "${MYSQL_ADMIN_USER=mysqladmin}"
    }
  }
}
```

- `${AZURE_ENV_NAME}` - Automatically set by azd (your environment name)
- `${AZURE_LOCATION}` - Automatically set by azd (your selected region)
- `${MYSQL_ADMIN_PASSWORD}` - Must be set via `azd env set`
- `${MYSQL_ADMIN_USER=mysqladmin}` - Has a default value of `mysqladmin`

## Hooks

### Post-Provision Hook

The post-provision hook runs after infrastructure provisioning and is available in both Bash and PowerShell versions:

- **Linux/macOS/WSL**: `infra/hooks/postprovision.sh` (Bash)
- **Windows**: `infra/hooks/postprovision.ps1` (PowerShell)

**What it does:**
1. Validates Azure CLI is installed
2. Verifies user is logged in to Azure
3. Checks current subscription matches azd target subscription (if set)
4. Retrieves storage account name and resource group from azd environment
5. Gets storage account key using Azure CLI
6. Uploads `nginx.conf` to the `nginx-config` NFS share

**Configuration in azure.yaml:**
```yaml
hooks:
  postprovision:
    # For Unix-like systems (Linux, macOS, WSL)
    posix:
      shell: sh
      run: ./infra/hooks/postprovision.sh
      continueOnError: false
    # For Windows systems (PowerShell)
    windows:
      shell: pwsh
      run: ./infra/hooks/postprovision.ps1
      continueOnError: false
```

The appropriate script is automatically selected based on your operating system.

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy WordPress

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install azd
        uses: Azure/setup-azd@v1.0.0
      
      - name: Login to Azure
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Deploy
        run: |
          azd env new production
          azd env set MYSQL_ADMIN_PASSWORD ${{ secrets.MYSQL_PASSWORD }}
          azd up --no-prompt
```

### Azure DevOps Example

```yaml
trigger:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

steps:
  - task: AzureCLI@2
    displayName: 'Install azd'
    inputs:
      azureSubscription: 'your-service-connection'
      scriptType: 'bash'
      scriptLocation: 'inlineScript'
      inlineScript: |
        curl -fsSL https://aka.ms/install-azd.sh | bash
        
  - task: AzureCLI@2
    displayName: 'Deploy with azd'
    inputs:
      azureSubscription: 'your-service-connection'
      scriptType: 'bash'
      scriptLocation: 'inlineScript'
      inlineScript: |
        azd env new production
        azd env set MYSQL_ADMIN_PASSWORD $(MYSQL_PASSWORD)
        azd up --no-prompt
```

## Naming Constraints

### Environment Name

**Critical constraint**: 1-9 characters, lowercase letters and numbers only.

**Why?** The environment name is used to generate Azure resource names:
- Storage Account: `st{env}{suffix}` (max 24 chars, lowercase/numbers only)
- MySQL Server: `mysql-{env}-{suffix}` (max 63 chars)
- Redis: `redis-{env}-{suffix}` (max 63 chars)
- VNet: `vnet-{env}` (max 64 chars)
- Container App Environment: `cae-{env}` (max 32 chars)
- Container App: `ca-{sitename}-{env}` (max 32 chars)

**Valid examples**: `wprod`, `wdev`, `wstaging`, `wp1`, `prod01`

**Invalid examples**: 
- `wp-prod` ❌ (contains hyphen)
- `WordPress` ❌ (contains uppercase)
- `wordpress-prod` ❌ (too long + hyphen)

## Troubleshooting

### azd command not found

Ensure azd is installed and in your PATH:
```bash
azd version
```

If not installed, see [Installation](#installation).

### Authentication errors

Re-authenticate:
```bash
azd auth login
```

### Missing environment variables

Check what's set:
```bash
azd env get-values
```

Set missing variables:
```bash
azd env set MYSQL_ADMIN_PASSWORD 'YourPassword123!'
```

### Deployment fails with "environment name too long"

Your environment name must be 1-9 characters:
```bash
azd init  # Create new environment with shorter name
```

### Post-provision hook fails

Run it manually to see detailed errors:

**Bash (Linux/macOS/WSL):**
```bash
./infra/hooks/postprovision.sh
```

**PowerShell (Windows):**
```powershell
./infra/hooks/postprovision.ps1
```

Common issues:
- Azure CLI not installed or not in PATH
- Not logged in to Azure (run `az login`)
- Subscription mismatch (ensure you're using the correct subscription)
- Storage account not yet ready (wait a minute and retry)
- NFS share not created (check Bicep deployment)

### View deployment logs

```bash
# View azd deployment logs
azd show

# View Azure deployment logs
az deployment group show \
  --name <deployment-name> \
  --resource-group rg-<env-name> \
  --query properties.error
```

## Migration from Legacy Scripts

If you're currently using `deploy.sh` or `deploy.ps1`:

1. **Your Bicep code remains the same** - moved to `infra/` directory
2. **nginx.conf upload is automated** - via postprovision hook
3. **Parameters are simpler** - use environment variables instead of prompts
4. **Resource group naming** - uses pattern `rg-<env-name>`

### Migration steps:

1. Install azd (see [Installation](#installation))
2. Run `azd init` to create an environment
3. Set your parameters with `azd env set`
4. Deploy with `azd up`

Your existing `deploy.sh` and `deploy.ps1` scripts will continue to work but are considered legacy.

## Advanced Configuration

### Custom Resource Group Name

azd uses `rg-<env-name>` by default. To use a custom name, set it before provisioning:

```bash
azd env set AZURE_RESOURCE_GROUP_NAME 'my-custom-rg'
azd provision
```

### Multiple Environments

Deploy to different environments (dev, staging, prod):

```bash
# Development
azd env new dev
azd env set MYSQL_ADMIN_PASSWORD 'DevPassword123!'
azd up

# Production
azd env new prod
azd env set MYSQL_ADMIN_PASSWORD 'ProdPassword123!'
azd up

# Switch between them
azd env select dev
azd show

azd env select prod
azd show
```

### Use Different Azure Subscription

```bash
azd env set AZURE_SUBSCRIPTION_ID '<subscription-id>'
azd up
```

## Resources

- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [azd GitHub Repository](https://github.com/Azure/azure-dev)
- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Project README](./README.md)
- [Architecture Documentation](./ARCHITECTURE.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
