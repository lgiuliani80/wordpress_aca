# Quick Reference

## Quick Start Commands

### Deploy with Azure Developer CLI (azd) - **Recommended**
```bash
# Install azd (one-time)
curl -fsSL https://aka.ms/install-azd.sh | bash

# Login and deploy
azd auth login
azd init
azd env set MYSQL_ADMIN_PASSWORD 'YourStr0ng!Password'
azd up
```

**Learn more**: See [AZD_GUIDE.md](./AZD_GUIDE.md) for comprehensive azd documentation.

### Deploy with Legacy Script (Bash)
```bash
chmod +x deploy.sh
./deploy.sh
```

### Deploy with Legacy Script (PowerShell)
```powershell
.\deploy.ps1
```

### Deploy with Azure CLI (Manual)
```bash
# Login
az login

# Create resource group
az group create --name rg-wordpress-aca --location norwayeast

# Deploy (using infra/ directory)
az deployment group create \
  --resource-group rg-wordpress-aca \
  --template-file infra/main.bicep \
  --parameters environmentName='wprod' \
  --parameters location='norwayeast' \
  --parameters mysqlAdminUser='mysqladmin' \
  --parameters mysqlAdminPassword='YourStr0ng!Password'
```

## Resource Names Pattern

| Resource Type | Pattern | Example |
|--------------|---------|---------|
| Storage Account | `st{env}{uniqueId}` | `stwpprodabc123` |
| MySQL Server | `mysql-{env}-{uniqueId}` | `mysql-wordpress-prod-abc123` |
| VNet | `vnet-{env}` | `vnet-wordpress-prod` |
| Container App Env | `cae-{env}` | `cae-wordpress-prod` |
| Container App | `ca-wordpress-{env}` | `ca-wordpress-wordpress-prod` |

## Default Subnets

| Subnet | CIDR | Purpose |
|--------|------|---------|
| container-apps-subnet | 10.0.0.0/23 | Container Apps Environment |
| private-endpoints-subnet | 10.0.2.0/24 | Private Endpoints |
| mysql-subnet | 10.0.3.0/24 | MySQL Flexible Server |

## Default Resources

| Component | SKU/Size | Notes |
|-----------|----------|-------|
| Storage Account | Premium_LRS | FileStorage with NFS 4.1 |
| MySQL Server | Standard_B1ms | Burstable, 1 vCore, 2 GB RAM |
| Container App (Nginx) | 1.0 CPU, 2 GB | Reverse proxy (25% of D4) |
| Container App (PHP) | 3.0 CPU, 6 GB | WordPress/PHP-FPM (75% of D4) |
| Workload Profile | D4 | 4 vCPU, 16 GB per node (2 replicas/node) |

## Key URLs & Endpoints

### After Deployment
```bash
# Get WordPress URL
az containerapp show \
  --name ca-wordpress-YOUR_ENV \
  --resource-group rg-wordpress-aca \
  --query "properties.configuration.ingress.fqdn" -o tsv

# Get MySQL FQDN
az mysql flexible-server show \
  --resource-group rg-wordpress-aca \
  --name mysql-YOUR_ENV-ID \
  --query "fullyQualifiedDomainName" -o tsv

# Get Storage Account Name
az storage account list \
  --resource-group rg-wordpress-aca \
  --query "[0].name" -o tsv
```

## Common Management Commands

### Azure Developer CLI (azd) Commands

```bash
# Deploy/update everything
azd up

# Provision infrastructure only
azd provision

# View deployment status and outputs
azd show

# List environments
azd env list

# Switch environment
azd env select <env-name>

# Set/view environment variables
azd env set MYSQL_ADMIN_PASSWORD 'NewPassword123!'
azd env get-values

# Delete all resources
azd down

# View logs (via Azure CLI integration)
azd exec -- az containerapp logs show --name ca-wpsite-YOUR_ENV --resource-group rg-YOUR_ENV --follow
```

### Azure CLI Management Commands

### View Logs
```bash
# All logs
az containerapp logs show --name ca-wordpress-YOUR_ENV --resource-group rg-wordpress-aca --follow

# Last 100 lines
az containerapp logs show --name ca-wordpress-YOUR_ENV --resource-group rg-wordpress-aca --tail 100
```

### Scale Manually
```bash
# Update min/max replicas
az containerapp update \
  --name ca-wordpress-YOUR_ENV \
  --resource-group rg-wordpress-aca \
  --min-replicas 2 \
  --max-replicas 5
```

### Restart Container App
```bash
# Create a new revision
az containerapp revision copy \
  --name ca-wordpress-YOUR_ENV \
  --resource-group rg-wordpress-aca
```

### Update Environment Variables
```bash
az containerapp update \
  --name ca-wordpress-YOUR_ENV \
  --resource-group rg-wordpress-aca \
  --set-env-vars "NEW_VAR=value"
```

### Connect to MySQL
```bash
# From local machine (requires VPN or bastion)
mysql -h MYSQL_FQDN -u mysqladmin -p wordpress

# From container
az containerapp exec \
  --name ca-wordpress-YOUR_ENV \
  --resource-group rg-wordpress-aca \
  --container php-fpm \
  --command "mysql -h MYSQL_FQDN -u mysqladmin -p"
```

## Monitoring

### View Metrics in Portal
```
Azure Portal → Container App → Monitoring → Metrics
- CPU Usage
- Memory Usage
- HTTP Request Count
- HTTP Request Duration
```

### Query Logs in Log Analytics
```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s contains "wordpress"
| order by TimeGenerated desc
| take 100
```

## Cost Estimation (Monthly, West Europe)

| Component | Estimated Cost |
|-----------|---------------|
| Container Apps Environment (Workload Profile D4) | ~$300 |
| Container Apps Compute | ~$100 |
| MySQL Flexible Server (B1ms) | ~$15 |
| Premium Storage (100 GB) | ~$20 |
| Networking (VNet, Private Endpoints) | ~$10 |
| Log Analytics | ~$5 |
| **Total** | **~$450/month** |

*Note: Costs vary by region and usage. Use Azure Pricing Calculator for accurate estimates.*

## Customization Quick Reference

### Change Scaling Limits
Edit `main.bicep`:
```bicep
scale: {
  minReplicas: 1    // Change min
  maxReplicas: 10   // Change max
}
```

### Change MySQL Tier
Edit `main.bicep`:
```bicep
sku: {
  name: 'Standard_D2ds_v4'  // Upgrade to General Purpose
  tier: 'GeneralPurpose'
}
```

### Change Container Images
Edit `parameters.json`:
```json
{
  "wordpressImage": { "value": "wordpress:latest" },
  "nginxImage": { "value": "nginx:latest" }
}
```

### Adjust Nginx Upload Limit
Edit `nginx.conf`:
```nginx
client_max_body_size 500M;  // Increase upload limit
```

## Backup & Restore

### Manual MySQL Backup
```bash
mysqldump -h MYSQL_FQDN -u mysqladmin -p wordpress > backup.sql
```

### Restore MySQL Backup
```bash
mysql -h MYSQL_FQDN -u mysqladmin -p wordpress < backup.sql
```

### Backup WordPress Files
```bash
# Mount the file share locally and copy
az storage file download-batch \
  --account-name STORAGE_ACCOUNT \
  --source wordpress \
  --destination ./wordpress-backup
```

## Security Checklist

- [ ] Use strong MySQL password (>12 characters)
- [ ] Enable Azure Defender for Cloud
- [ ] Configure custom domain with HTTPS
- [ ] Enable MySQL SSL enforcement
- [ ] Review storage account firewall rules
- [ ] Set up Azure Key Vault for secrets
- [ ] Enable diagnostic logging
- [ ] Configure backup retention
- [ ] Review and limit RBAC permissions
- [ ] Enable Azure WAF (if using Front Door)

## Cleanup

### Using Azure Developer CLI (azd)
```bash
# Delete all resources (keeps environment config)
azd down

# Delete environment config too
azd env remove <environment-name>
```

### Using Azure CLI

#### Delete Everything
```bash
az group delete --name rg-wordpress-aca --yes --no-wait
```

#### Delete Specific Resources
```bash
# Delete Container App only
az containerapp delete --name ca-wordpress-YOUR_ENV --resource-group rg-wordpress-aca --yes

# Delete MySQL only
az mysql flexible-server delete --resource-group rg-wordpress-aca --name mysql-YOUR_ENV-ID --yes
```

## Support & Resources

- **Azure Developer CLI Guide**: See [AZD_GUIDE.md](./AZD_GUIDE.md)
- **General Documentation**: See [README.md](./README.md)
- **Architecture Details**: See [ARCHITECTURE.md](./ARCHITECTURE.md)
- **Troubleshooting**: See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- **Azure Container Apps**: https://docs.microsoft.com/azure/container-apps/
- **Azure Developer CLI**: https://learn.microsoft.com/azure/developer/azure-developer-cli/
- **WordPress Docs**: https://wordpress.org/documentation/
- **Issues**: Create issue in GitHub repository
- **Azure Support**: Open ticket in Azure Portal
