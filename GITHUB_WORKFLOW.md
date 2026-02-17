# GitHub Actions Workflow Setup Guide

This guide explains how to set up and use the GitHub Actions workflow for deploying WordPress on Azure Container Apps using Azure Developer CLI (azd).

## Prerequisites

Before using the workflow, you need to set up the following:

### 1. Azure Service Principal with OIDC (Federated Credentials)

The workflow uses OpenID Connect (OIDC) for secure authentication to Azure without storing credentials.

#### Steps to create the service principal with federated credentials:

1. **In Azure Portal:**
   - Create an App Registration in Microsoft Entra ID (formerly Azure Active Directory)
   - Note the Application (client) ID and Directory (tenant) ID
   - Under "Certificates & secrets", go to "Federated credentials"
   - Click "Add credential"
   - Select "GitHub Actions deploying Azure resources"
   - Fill in:
     - **Organization**: Your GitHub organization or username
     - **Repository**: Your repository name (e.g., `wordpress_aca`)
     - **Entity type**: Environment
     - **Environment name**: `dev` (create separate credentials for `staging` and `prod` too)
     - **Name**: A descriptive name (e.g., "github-wordpress-dev")
   - Click "Add"
   - Repeat this process for each environment (dev, staging, prod)

2. **Assign permissions to the App Registration:**
   - Go to your Azure Subscription
   - Click "Access control (IAM)"
   - Add role assignment: "Contributor" (or appropriate role)
   - Assign to the App Registration you created

### 2. Configure GitHub Secrets

The following secrets must be configured at the repository level:

1. Go to your GitHub repository
2. Navigate to Settings → Secrets and variables → Actions
3. Add the following **Repository secrets**:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `AZURE_CLIENT_ID` | Application (client) ID from App Registration | `12345678-1234-1234-1234-123456789012` |
| `AZURE_TENANT_ID` | Directory (tenant) ID from App Registration | `87654321-4321-4321-4321-210987654321` |
| `AZURE_SUBSCRIPTION_ID` | Your Azure subscription ID | `abcdef01-2345-6789-abcd-ef0123456789` |
| `MYSQL_ADMIN_PASSWORD` | MySQL admin password (min 8 chars, upper/lower/number/special) | `P@ssw0rd123!` |

### 3. Configure GitHub Environment Variables

GitHub supports environment-specific variables. Configure these for each environment (dev, staging, prod):

1. Go to Settings → Environments
2. Create or select an environment (e.g., "dev")
3. Add the following **Environment variables**:

#### Required Variables:

| Variable Name | Description | Example |
|---------------|-------------|---------|
| `AZURE_ENV_NAME` | Environment name (1-9 lowercase/numbers) | `dev`, `prod1` |
| `AZURE_LOCATION` | Azure region | `eastus`, `westeurope` |

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

1. Go to Settings → Environments → Select environment (e.g., "dev")
2. Under "Environment variables", click "Add variable"
3. Add each variable with appropriate values

### 4. Configure Environment Protection Rules (Optional)

For production environments, you may want to add protection rules:

1. Go to Settings → Environments → Select environment (e.g., "prod")
2. Under "Deployment protection rules":
   - Add required reviewers
   - Set wait timer
   - Configure deployment branches (e.g., only `main` branch)

## Running the Workflow

### Manual Trigger (workflow_dispatch)

1. Go to Actions tab in your GitHub repository
2. Select "Deploy WordPress to Azure" workflow
3. Click "Run workflow"
4. Select:
   - **Branch**: Usually `main`
   - **Environment**: `dev`, `staging`, or `prod`
   - **Resource Group Name** (required): Specify the resource group name
5. Click "Run workflow"

### Reusable Workflow (workflow_call)

The workflow can also be called from other workflows in your repository. This allows you to create composite workflows or trigger deployments from other automation pipelines.

Example of calling this workflow from another workflow:

```yaml
jobs:
  deploy-wordpress:
    uses: ./.github/workflows/deploy.yml
    with:
      environment: 'dev'
      resourceGroup: 'rg-wordpress-dev'
    secrets:
      AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
      AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
      AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      MYSQL_ADMIN_PASSWORD: ${{ secrets.MYSQL_ADMIN_PASSWORD }}
```

### Workflow Execution

The workflow will:
1. Checkout the code
2. Install Azure Developer CLI
3. Authenticate to Azure using OIDC (no credentials stored!)
4. Validate all required variables (ensures none are null)
5. Create the resource group if it doesn't exist in the specified location
6. Set environment variables from GitHub
7. Run `azd up --no-prompt` to provision infrastructure and deploy

## Workflow Configuration

The workflow is defined in `.github/workflows/deploy.yml`:

### Trigger Configuration
```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment'
        required: true
        default: 'dev'
        type: choice
        options:
          - dev
          - staging
          - prod
      resourceGroup:
        description: 'Resource Group Name'
        required: true
        type: string
  workflow_call:
    inputs:
      environment:
        description: 'Environment'
        required: false
        default: 'dev'
        type: string
      resourceGroup:
        description: 'Resource Group Name'
        required: true
        type: string
    secrets:
      AZURE_CLIENT_ID:
        required: true
      AZURE_TENANT_ID:
        required: true
      AZURE_SUBSCRIPTION_ID:
        required: true
      MYSQL_ADMIN_PASSWORD:
        required: true
```

### OIDC Authentication
```yaml
- name: Azure Login (OIDC)
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### Resource Group Handling
The workflow requires the resource group name as a mandatory input parameter. The workflow will:
1. Check if the resource group exists
2. If it exists, use it (and log a warning if location differs)
3. If it doesn't exist, create it in the specified `AZURE_LOCATION`
4. If location differs, update `AZURE_LOCATION` to match existing RG location

### Environment Variable Mapping
All parameters are read from GitHub secrets/variables and passed to azd. The workflow validates that all truly required variables are not null before proceeding:

**Required variables (validation fails if null):**
- `AZURE_ENV_NAME`, `AZURE_LOCATION`, `MYSQL_ADMIN_PASSWORD`
- `resourceGroup` (workflow input parameter)

**Optional with defaults (automatically set if not provided):**
- `MYSQL_ADMIN_USER` (default: `mysqladmin`)
- `WORDPRESS_DB_NAME` (default: `wordpress`)
- `SITE_NAME` (default: `wpsite`)
- `WORDPRESS_IMAGE` (default: `wordpress:php8.2-fpm`)
- `NGINX_IMAGE` (default: `nginx:alpine`)
- `ALLOWED_IP_ADDRESS` (default: empty = no IP restrictions)
- `PHP_SESSIONS_IN_REDIS` (default: `false`)

## Security Best Practices

1. **OIDC Authentication**: No long-lived credentials stored in GitHub
2. **Secret Variables**: Use GitHub Secrets for sensitive data (passwords, client IDs)
3. **Environment Protection**: Configure approval gates for production deployments
4. **Least Privilege**: Grant only necessary permissions to the service principal
5. **Variable Scoping**: Scope variables to specific environments
6. **Branch Protection**: Use deployment branches to restrict which branches can deploy

## Troubleshooting

### Workflow fails with "ERROR: [Variable] is required and cannot be empty"
- Ensure all required variables are set in the environment or as secrets
- Check that variable names match exactly (case-sensitive)
- Verify that variables are not empty strings

### Workflow fails with "ERROR: Resource Group is required"
- The resource group name is now a required parameter
- Provide the resource group name as an input when running the workflow

### Resource group creation fails
- Verify the service principal has permission to create resource groups
- Check that the location name is valid (e.g., `eastus`, `westeurope`)
- Ensure there are no Azure Policy restrictions preventing resource group creation

### OIDC authentication fails
- Verify the federated credentials are configured correctly in Azure
- Check that the entity type matches (Environment)
- Ensure the environment name in GitHub matches the federated credential
- Verify the service principal has appropriate permissions on the subscription

### Workflow fails with "azd: command not found"
- The workflow automatically installs azd, but if it fails:
  - Check the installation step logs
  - Verify the runner can access https://aka.ms/install-azd.sh

### Deployment validation errors
- The preprovision hook validates parameters before deployment
- Check the validation error messages for specific issues
- Ensure environment name is 1-9 characters (lowercase/numbers)
- Ensure MySQL password meets complexity requirements

## Differences from Azure DevOps Pipeline

If migrating from Azure DevOps:

| Aspect | Azure DevOps | GitHub Actions |
|--------|--------------|----------------|
| Trigger | `workflow_dispatch` parameter | `workflow_dispatch` input |
| Authentication | Service Connection | OIDC with secrets |
| Variables | Pipeline variables | Environment variables + secrets |
| Environments | Pipeline environments | Repository environments |
| OIDC Setup | Service connection | Federated credentials per environment |
| Secrets | Pipeline secrets/variables | Repository/environment secrets |

## Next Steps

After successful deployment:
1. Check the workflow run logs for deployed resources
2. Access the WordPress site using the URL provided in the output
3. Configure WordPress settings as needed
4. Set up monitoring and alerts in Azure Portal

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Azure Login Action](https://github.com/Azure/login)
- [OIDC with Azure](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Project AZD_GUIDE.md](./AZD_GUIDE.md) - Detailed azd deployment guide
- [Project README.md](./README.md) - WordPress on Azure Container Apps overview
