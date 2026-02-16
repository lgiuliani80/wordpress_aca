# Migration Guide: Deployment with Azure Developer CLI (azd)

This guide explains the current deployment approach using Azure Developer CLI (azd) with automatic parameter validation.

## Current Structure

### Files and Organization

```
wordpress_aca/
├── azure.yaml                      # azd configuration with preprovision and postprovision hooks
├── .azure/                         # azd environments (gitignored)
├── .env.template                   # Environment variables template
├── .azdignore                      # azd ignore patterns
├── AZD_GUIDE.md                    # Comprehensive azd documentation
├── infra/                          # Infrastructure directory
│   ├── main.bicep                  # Bicep template (with azd-specific outputs)
│   ├── main.parameters.json        # azd parameter file with variable substitution
│   ├── nginx.conf                  # Nginx configuration
│   └── hooks/
│       ├── preprovision.sh         # Pre-provision parameter validation (Bash)
│       ├── preprovision.ps1        # Pre-provision parameter validation (PowerShell)
│       ├── postprovision.sh        # Post-provision automation (Bash)
│       └── postprovision.ps1       # Post-provision automation (PowerShell)
├── main.bicep                      # Root-level Bicep (for backward compatibility)
├── nginx.conf                      # Root-level nginx.conf (for backward compatibility)
├── parameters.json                 # Root-level parameters (for backward compatibility)
└── parameters.dev.json             # Root-level dev parameters (for backward compatibility)
```

## Why Azure Developer CLI?

Azure Developer CLI (azd) provides:

✅ **Automatic Parameter Validation**: Preprovision hooks validate all parameters before deployment  
✅ **Simpler Commands**: `azd up` instead of running scripts with multiple prompts  
✅ **Environment Management**: Easy switching between dev, staging, prod environments  
✅ **Better CI/CD Integration**: Cleaner automation with environment variables  
✅ **Standardized Structure**: Follows Azure best practices for IaC projects  
✅ **Lifecycle Management**: Built-in support for provision, deploy, down commands  
✅ **Extensibility**: Hooks for custom automation and validation  

## Migration Options

### Option 1: Fresh Start with azd (Recommended)

Best for new deployments or when you want a clean slate.

**Steps:**

1. **Install azd**
   ```bash
   curl -fsSL https://aka.ms/install-azd.sh | bash
   ```

2. **Initialize and deploy**
   ```bash
   cd wordpress_aca
   azd auth login
   azd init
   azd env set MYSQL_ADMIN_PASSWORD 'YourSecurePassword123!'
   azd up
   ```

3. **Done!** Your WordPress site is deployed.

### Option 2: Continue Using Legacy Scripts

If you prefer to keep using the existing scripts:

**What you need to know:**

- Legacy scripts (`deploy.sh`, `deploy.ps1`) still work
- They now reference `infra/main.bicep` if you want to use the updated version
- Or continue using `main.bicep` in root (both are maintained for compatibility)
- Parameters files (`parameters.json`, `parameters.dev.json`) still work

**No changes required** - your existing workflow continues to function.

### Option 3: Hybrid Approach

Use azd for some environments, legacy scripts for others:

```bash
# Development with azd
azd env new dev
azd env set MYSQL_ADMIN_PASSWORD 'DevPass123!'
azd up

# Production with legacy script (if you have specific requirements)
./deploy.sh
```

## Comparison: Legacy vs azd

| Aspect | Legacy Scripts | Azure Developer CLI (azd) |
|--------|---------------|---------------------------|
| **Installation** | Azure CLI only | Azure CLI + azd |
| **Setup** | Run script, answer prompts | Set env vars, run `azd up` |
| **Parameters** | Interactive prompts | Environment variables |
| **Multi-environment** | Run script multiple times | `azd env new/select` |
| **CI/CD** | Complex scripting | Simple `azd up --no-prompt` |
| **Resource Group** | Custom name via prompt | `rg-{env-name}` pattern |
| **nginx.conf Upload** | In script | Automatic via hook |
| **Updates** | Re-run entire script | `azd provision` |
| **Cleanup** | Manual `az group delete` | `azd down` |

## Environment Variables Mapping

### Legacy Script Prompts → azd Environment Variables

| Legacy Script Prompt | azd Environment Variable | Default | Required |
|---------------------|--------------------------|---------|----------|
| Environment Name | `AZURE_ENV_NAME` | - | Yes (via `azd init`) |
| Location | `AZURE_LOCATION` | - | Yes (via `azd up`) |
| MySQL Admin Username | `MYSQL_ADMIN_USER` | `mysqladmin` | No |
| MySQL Admin Password | `MYSQL_ADMIN_PASSWORD` | - | Yes |
| Resource Group Name | `AZURE_RESOURCE_GROUP_NAME` | `rg-{env}` | No |
| WordPress DB Name | `WORDPRESS_DB_NAME` | `wordpress` | No |
| WordPress Image | `WORDPRESS_IMAGE` | `wordpress:php8.2-fpm` | No |
| Nginx Image | `NGINX_IMAGE` | `nginx:alpine` | No |
| Site Name | `SITE_NAME` | `wpsite` | No |
| Allowed IP Address | `ALLOWED_IP_ADDRESS` | (empty) | No |

## Setting Up Your First azd Environment

### Step-by-Step Guide

1. **Clone the repository** (if you haven't already)
   ```bash
   git clone <your-repository-url>
   cd wordpress_aca
   ```

2. **Install azd**
   ```bash
   # macOS/Linux
   curl -fsSL https://aka.ms/install-azd.sh | bash
   
   # Windows (PowerShell)
   powershell -ex AllSigned -c "Invoke-RestMethod 'https://aka.ms/install-azd.ps1' | Invoke-Expression"
   ```

3. **Login to Azure**
   ```bash
   azd auth login
   ```

4. **Initialize your first environment**
   ```bash
   azd init
   ```
   
   When prompted:
   - **Environment Name**: Enter a short name (1-9 chars, lowercase/numbers only)
     - Examples: `wprod`, `wdev`, `wtest`
   
5. **Set required parameters**
   ```bash
   # Required: MySQL password
   azd env set MYSQL_ADMIN_PASSWORD 'YourSecurePassword123!'
   
   # Optional: Override defaults
   azd env set MYSQL_ADMIN_USER 'mysqladmin'
   azd env set SITE_NAME 'wpsite'
   ```

6. **Deploy everything**
   ```bash
   azd up
   ```
   
   When prompted:
   - **Azure Subscription**: Select your subscription
   - **Azure Location**: Choose a region (e.g., `norwayeast`, `westeurope`)

7. **Access your WordPress site**
   
   After deployment completes, azd will display:
   - WordPress URL
   - Storage Account name
   - MySQL Server FQDN
   
   Navigate to the WordPress URL to complete the WordPress installation.

## Managing Multiple Environments

One of the biggest advantages of azd is easy environment management:

```bash
# Create development environment
azd env new dev
azd env set MYSQL_ADMIN_PASSWORD 'DevPassword123!'
azd up
# Choose location: norwayeast

# Create production environment
azd env new prod
azd env set MYSQL_ADMIN_PASSWORD 'ProdPassword123!'
azd up
# Choose location: westeurope

# Switch between environments
azd env select dev
azd show    # Shows dev environment

azd env select prod
azd show    # Shows prod environment

# List all environments
azd env list
```

Each environment is completely isolated with its own:
- Resource group
- Resources
- Configuration
- Location

## CI/CD Integration

### Before (Legacy Scripts)

```yaml
# Complex shell scripting with prompts
- name: Deploy WordPress
  run: |
    echo "${{ secrets.MYSQL_PASSWORD }}" | ./deploy.sh
    # Handle interactive prompts...
```

### After (azd)

```yaml
# Clean and simple
- name: Install azd
  uses: Azure/setup-azd@v1.0.0

- name: Deploy WordPress
  run: |
    azd env new production
    azd env set MYSQL_ADMIN_PASSWORD ${{ secrets.MYSQL_PASSWORD }}
    azd up --no-prompt
```

See [AZD_GUIDE.md](./AZD_GUIDE.md#cicd-integration) for complete CI/CD examples.

## Troubleshooting Migration

### Issue: "azd command not found"

**Solution**: Install azd
```bash
curl -fsSL https://aka.ms/install-azd.sh | bash
# Then restart your terminal
```

### Issue: "environment name too long"

**Solution**: Environment names must be 1-9 characters (lowercase/numbers only)
```bash
azd init  # Create new environment with shorter name
# Use: wprod, wdev, wtest (not: wordpress-prod, wp-production)
```

### Issue: "Missing MYSQL_ADMIN_PASSWORD"

**Solution**: Set the required password
```bash
azd env set MYSQL_ADMIN_PASSWORD 'YourSecurePassword123!'
```

### Issue: "Can't find infra directory"

**Solution**: Make sure you're in the repository root
```bash
cd wordpress_aca  # Repository root
ls infra/         # Should show main.bicep, nginx.conf, etc.
```

### Issue: "Post-provision hook failed"

**Solution**: Run it manually to see detailed errors
```bash
./infra/hooks/postprovision.sh
```

Common causes:
- Storage account not fully provisioned (wait 1-2 minutes, retry)
- Not logged in to Azure (`az login`)
- Missing permissions

## Frequently Asked Questions

### Q: Do I have to migrate to azd?

**A:** No. The legacy scripts (`deploy.sh`, `deploy.ps1`) continue to work. However, azd provides a better experience for most use cases.

### Q: What happens to my existing deployments?

**A:** Existing deployments are not affected. You can continue managing them with Azure CLI or the Azure Portal. azd is only for new deployments or if you want to migrate.

### Q: Can I use azd with my existing resource group?

**A:** Yes, but azd expects a specific naming pattern (`rg-{env-name}`). You can override this:
```bash
azd env set AZURE_RESOURCE_GROUP_NAME 'my-existing-rg'
azd provision
```

### Q: Will azd change my resource names?

**A:** Resource names are generated the same way (based on environment name). As long as you use the same environment name, resources will have the same names.

### Q: How do I migrate an existing deployment to azd management?

**A:** You cannot directly migrate. Create a new deployment with azd, then migrate data:
1. Deploy with azd to a new environment
2. Export data from old WordPress (database + files)
3. Import data to new WordPress
4. Update DNS to point to new deployment
5. Delete old deployment

### Q: Where are azd environment configurations stored?

**A:** In `.azure/<environment-name>/` directory (gitignored). Each environment has its own isolated configuration.

### Q: Can I have different parameters for different environments?

**A:** Yes! Each azd environment has its own environment variables:
```bash
azd env select dev
azd env set MYSQL_ADMIN_USER 'devadmin'

azd env select prod
azd env set MYSQL_ADMIN_USER 'prodadmin'
```

### Q: How do I see what's deployed in an environment?

**A:** Use `azd show`:
```bash
azd env select <environment-name>
azd show
```

This displays:
- Deployed resources
- Outputs (WordPress URL, Storage Account, etc.)
- Environment variables

## Getting Help

- **azd Documentation**: See [AZD_GUIDE.md](./AZD_GUIDE.md)
- **General Documentation**: See [README.md](./README.md)
- **Architecture**: See [ARCHITECTURE.md](./ARCHITECTURE.md)
- **Troubleshooting**: See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- **Quick Reference**: See [QUICK_REFERENCE.md](./QUICK_REFERENCE.md)

## Next Steps

After successful migration to azd:

1. ✅ Review the [AZD_GUIDE.md](./AZD_GUIDE.md) for detailed documentation
2. ✅ Set up multiple environments (dev, staging, prod)
3. ✅ Configure CI/CD pipelines with azd
4. ✅ Explore azd commands (`azd env`, `azd provision`, `azd down`)
5. ✅ Customize `infra/main.parameters.json` if needed

Welcome to the streamlined deployment experience with Azure Developer CLI! 🚀
