# Azure DevOps Pipeline Setup Guide

This guide explains how to set up and use the Azure DevOps pipeline for deploying WordPress on Azure Container Apps using Azure Developer CLI (azd).

## Prerequisites

Before using the pipeline, you need to set up the following:

### 1. Azure Service Connection with OIDC

The pipeline uses OpenID Connect (OIDC) for secure authentication to Azure without storing credentials.

#### Steps to create the service connection:

1. **In Azure Portal:**
   - Create an App Registration in Microsoft Entra ID (formerly Azure Active Directory)
   - Note the Application (client) ID and Directory (tenant) ID
   - Under "Certificates & secrets", go to "Federated credentials"
   - Add a new credential with:
     - Federated credential scenario: "Other issuer"
     - Issuer: `https://vstoken.dev.azure.com/<YOUR_ORGANIZATION_ID>`
     - Subject identifier: `sc://<YOUR_ORGANIZATION>/<YOUR_PROJECT>/<SERVICE_CONNECTION_NAME>`
     - Name: A descriptive name (e.g., "azdo-wordpress-oidc")

2. **Assign permissions to the App Registration:**
   - Go to your Azure Subscription
   - Click "Access control (IAM)"
   - Add role assignment: "Contributor" (or appropriate role)
   - Assign to the App Registration you created

3. **In Azure DevOps:**
   - Go to Project Settings → Service connections
   - Click "New service connection"
   - Select "Azure Resource Manager"
   - Choose "Workload Identity federation (automatic)" or "Workload Identity federation (manual)"
   - Fill in:
     - Service connection name: `azure-oidc-connection` (or update the variable in the pipeline)
     - Subscription ID
     - Subscription name
     - Service Principal ID (Application/Client ID from step 1)
     - Tenant ID
   - Grant access permission to all pipelines (or configure per-pipeline)

### 2. Environment Setup

Create an environment in Azure DevOps for each deployment target (dev, staging, prod):

1. Go to Pipelines → Environments
2. Create a new environment (e.g., "dev", "staging", "prod")
3. Configure environment variables for each environment

### 3. Configure Environment Variables

For each environment in Azure DevOps, configure the following variables:

#### Required Variables:

| Variable Name | Description | Example |
|---------------|-------------|---------|
| `AZURE_ENV_NAME` | Environment name (1-9 lowercase/numbers) | `dev`, `prod1` |
| `AZURE_LOCATION` | Azure region | `eastus`, `westeurope` |
| `AZURE_RESOURCE_GROUP` | Resource group name (required if not using parameter) | `rg-wordpress-dev` |
| `MYSQL_ADMIN_PASSWORD` | MySQL admin password (min 8 chars, upper/lower/number/special) | `P@ssw0rd123!` |

**Note**: Either `AZURE_RESOURCE_GROUP` variable or the pipeline `resourceGroup` parameter must be provided.

#### Optional Variables (with defaults):

| Variable Name | Default Value | Description |
|---------------|---------------|-------------|
| `MYSQL_ADMIN_USER` | `mysqladmin` | MySQL admin username |
| `WORDPRESS_DB_NAME` | `wordpress` | WordPress database name |
| `SITE_NAME` | `wpsite` | Site name for resource naming |
| `ALLOWED_IP_ADDRESS` | (empty) | IP address to allow access (empty = no IP restrictions) |
| `WORDPRESS_IMAGE` | `wordpress:php8.2-fpm` | WordPress Docker image |
| `NGINX_IMAGE` | `nginx:alpine` | Nginx Docker image |
| `PHP_SESSIONS_IN_REDIS` | `false` | Use Redis for PHP sessions |

#### How to set environment variables:

**Option 1: Environment-specific variables (Recommended)**
1. Go to Pipelines → Environments
2. Select your environment (e.g., "dev")
3. Click on the three dots → "Add variable"
4. Add each variable with appropriate values
5. Mark `MYSQL_ADMIN_PASSWORD` as secret

**Option 2: Pipeline variables**
1. Edit the pipeline
2. Click "Variables"
3. Add variables (can be scoped to stages)

**Option 3: Variable groups**
1. Go to Pipelines → Library
2. Create a variable group per environment
3. Link the variable group to the pipeline

## Running the Pipeline

### Manual Trigger (workflow_dispatch)

1. Go to Pipelines → Select the pipeline
2. Click "Run pipeline"
3. Select the **environment** parameter:
   - `dev` (default)
   - `staging`
   - `prod`
4. Enter the **Resource Group Name** parameter:
   - Leave empty to use the `AZURE_RESOURCE_GROUP` variable from the environment
   - Or specify a resource group name explicitly (e.g., `rg-wordpress-dev`)
5. Click "Run"

The pipeline will:
1. Install Azure Developer CLI
2. Authenticate to Azure using OIDC
3. Validate all required variables (ensures none are null)
4. Create the resource group if it doesn't exist in the specified location
5. Set environment variables from Azure DevOps
6. Run `azd up` to provision infrastructure and deploy

## Pipeline Configuration

The pipeline is defined in `azure-pipelines.yml` with the following key features:

### Trigger Configuration
```yaml
trigger: none  # Manual trigger only

parameters:
  - name: environment
    displayName: 'Environment'
    type: string
    default: 'dev'
  - name: resourceGroup
    displayName: 'Resource Group Name'
    type: string
    default: ''
```

### Resource Group Handling
The pipeline accepts the resource group name as a parameter. If not provided via parameter, it falls back to the `AZURE_RESOURCE_GROUP` environment variable. The pipeline will:
1. Check if the resource group exists
2. If it exists, use it (and log a warning if location differs)
3. If it doesn't exist, create it in the specified `AZURE_LOCATION`

### OIDC Authentication
```yaml
- task: AzureCLI@2
  inputs:
    azureSubscription: $(azureServiceConnection)
    addSpnToEnvironment: true
```

### Environment Variable Mapping
All parameters are read from Azure DevOps environment variables and passed to azd. The pipeline validates that all truly required variables are not null before proceeding:

**Required variables (validation fails if null):**
- `AZURE_ENV_NAME`, `AZURE_LOCATION`, `MYSQL_ADMIN_PASSWORD`
- `AZURE_RESOURCE_GROUP` (or provide via pipeline parameter)

**Optional with defaults (automatically set if not provided):**
- `MYSQL_ADMIN_USER` (default: `mysqladmin`)
- `WORDPRESS_DB_NAME` (default: `wordpress`)
- `SITE_NAME` (default: `wpsite`)
- `WORDPRESS_IMAGE` (default: `wordpress:php8.2-fpm`)
- `NGINX_IMAGE` (default: `nginx:alpine`)
- `ALLOWED_IP_ADDRESS` (default: empty = no IP restrictions)
- `PHP_SESSIONS_IN_REDIS` (default: `false`)

**Resource Group Handling:**
- Must be specified via pipeline parameter OR `AZURE_RESOURCE_GROUP` variable
- Pipeline creates it if it doesn't exist in the specified `AZURE_LOCATION`
- If resource group exists in a different location, `AZURE_LOCATION` is updated to match

## Security Best Practices

1. **OIDC Authentication**: No credentials stored in Azure DevOps
2. **Secret Variables**: Mark `MYSQL_ADMIN_PASSWORD` as secret
3. **Environment Protection**: Configure approval gates for production
4. **Least Privilege**: Grant only necessary permissions to the service principal
5. **Variable Scoping**: Scope variables to specific environments

## Troubleshooting

### Pipeline fails with "ERROR: [Variable] is required and cannot be empty"
- Ensure all required variables are set in the environment or pipeline variables
- Check that variable names match exactly (case-sensitive)
- Verify that variables are not empty strings

### Pipeline fails with "ERROR: Resource Group is required"
- Provide the resource group name either:
  - As a parameter when running the pipeline, OR
  - Set the `AZURE_RESOURCE_GROUP` variable in the environment

### Resource group creation fails
- Verify the service principal has permission to create resource groups
- Check that the location name is valid (e.g., `eastus`, `westeurope`)
- Ensure there are no Azure Policy restrictions preventing resource group creation

### Pipeline fails with "AZURE_ENV_NAME is required"
- Ensure the variable is set in the environment or pipeline variables

### Authentication fails
- Verify the service connection is configured correctly
- Check that federated credentials are set up properly
- Ensure the service principal has Contributor role on the subscription

### azd command not found
- The pipeline automatically installs azd, but if it fails:
  - Check the installation step logs
  - Verify the agent can access https://aka.ms/install-azd.sh

### Deployment validation errors
- The preprovision hook validates parameters before deployment
- Check the validation error messages for specific issues
- Ensure environment name is 1-9 characters (lowercase/numbers)
- Ensure MySQL password meets complexity requirements

## Next Steps

After successful deployment:
1. Check the pipeline output for the deployed resources
2. Access the WordPress site using the URL provided in the output
3. Configure WordPress settings as needed
4. Set up monitoring and alerts in Azure Portal

## Additional Resources

- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Azure DevOps OIDC Documentation](https://learn.microsoft.com/azure/devops/pipelines/library/connect-to-azure)
- [Project AZD_GUIDE.md](./AZD_GUIDE.md) - Detailed azd deployment guide
- [Project README.md](./README.md) - WordPress on Azure Container Apps overview
