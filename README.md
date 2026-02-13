# WordPress on Azure Container Apps with NFS Storage

This project provides Infrastructure as Code (IaC) using Azure Bicep to deploy a production-ready WordPress solution on Azure Container Apps with the following features:

## Features

- ✅ **WordPress on Container Apps**: Scalable WordPress hosting using Azure Container Apps with Workload Profiles
- ✅ **NFS Storage**: WordPress files mounted via NFS on Premium Storage Account for high performance
- ✅ **Private Networking**: All services communicate through private endpoints
- ✅ **FastCGI**: WordPress runs with PHP-FPM and Nginx as reverse proxy for optimal performance
- ✅ **MySQL Flexible Server**: Private MySQL database with VNet integration
- ✅ **Auto-scaling**: Automatic scaling based on HTTP load

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Virtual Network                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Container Apps Subnet (10.0.0.0/23)                 │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │  WordPress Container App (Workload Profile D4) │  │   │
│  │  │  ├─ Nginx (reverse proxy)                      │  │   │
│  │  │  └─ PHP-FPM (FastCGI)                          │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  MySQL Subnet (10.0.3.0/24)                          │   │
│  │  └─ MySQL Flexible Server (Private)                  │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Private Endpoints Subnet (10.0.2.0/24)              │   │
│  │  └─ Storage Account Private Endpoint (NFS)           │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- Bicep CLI (included with Azure CLI 2.20.0+)

## Deployment

### 1. Clone the repository

```bash
git clone <your-repository-url>
cd wordpress_aca
```

### 2. Update parameters

Edit `parameters.json` and update the following values:

- `environmentName`: Unique name for your environment (1-9 characters, lowercase letters and numbers only, no hyphens or special characters)
- `mysqlAdminPassword`: Strong password for MySQL admin (min 8 characters, must include uppercase, lowercase, numbers, and special characters)
- `location`: Azure region (e.g., `westeurope`, `eastus`)

**Important Naming Constraints**:
- **Environment Name**: Must be 1-9 characters, lowercase letters and numbers only (no hyphens, underscores, or special characters). This is used to generate resource names including the storage account which has strict naming rules.
- Examples of valid names: `wprod`, `wdev`, `wstaging`, `wp1`, `prod01`
- Examples of invalid names: `wp-prod` (hyphen), `WordPress` (uppercase), `wordpress-prod` (too long + hyphen)

**Important**: Never commit real passwords to version control. Use Azure Key Vault references or pass them as secure parameters during deployment.

### 3. Deploy using automated scripts

**Option A: Using Bash (Linux/macOS/WSL)**
```bash
chmod +x deploy.sh
./deploy.sh
```

**Option B: Using PowerShell (Windows/PowerShell Core)**
```powershell
.\deploy.ps1
```

The deployment scripts will:
- Verify Azure CLI installation and authentication
- Prompt for deployment parameters with validation
- Validate parameter constraints:
  - Resource group name (1-90 chars, alphanumeric, -, _, ., ())
  - Environment name (1-9 chars, lowercase/numbers only)
  - MySQL username (1-16 chars, alphanumeric only)
  - MySQL password complexity (min 8 chars, upper/lower/number/special)
  - Ensure all generated resource names stay within Azure limits
- Create the resource group
- Deploy the Bicep template
- Upload nginx.conf to the NFS share

### 4. Deploy using Azure CLI manually

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Create resource group
az group create --name rg-wordpress-aca --location westeurope

# Deploy the Bicep template
az deployment group create \
  --resource-group rg-wordpress-aca \
  --template-file main.bicep \
  --parameters parameters.json \
  --parameters mysqlAdminPassword='YOUR_MYSQL_PASSWORD'
```

### 5. Alternative: Deploy with parameter file only

For CI/CD pipelines, you can also deploy with all parameters in the file:

```bash
az deployment group create \
  --resource-group rg-wordpress-aca \
  --template-file main.bicep \
  --parameters @parameters.json
```

## Post-Deployment

After successful deployment, the output will include:

- `wordpressUrl`: The public URL of your WordPress site
- `storageAccountName`: Name of the storage account with NFS share
- `mysqlServerFqdn`: FQDN of the MySQL server

### Access WordPress

1. Navigate to the `wordpressUrl` shown in the output
2. Complete the WordPress installation wizard
3. Use the admin credentials you specified

### Initial WordPress Setup

Since WordPress files are stored on NFS, the first container instance will initialize the WordPress files. This may take a few minutes on first startup.

## Architecture Details

### Storage Configuration

- **Storage Account**: Premium FileStorage with NFS 4.1 support
- **WordPress NFS Share**: Mounted at `/var/www/html` in both Nginx and PHP-FPM containers (NFS 4.1 protocol)
- **Nginx Config NFS Share**: Mounted at `/etc/nginx` in Nginx container (NFS 4.1 protocol)
- **Private Endpoint**: Storage accessible only through private network
- **Deploy Script**: Automatically uploads nginx.conf to NFS share after deployment

### Networking

- **VNet**: 10.0.0.0/16 address space
- **Container Apps Subnet**: 10.0.0.0/23 (delegated to Container Apps)
- **Private Endpoints Subnet**: 10.0.2.0/24
- **MySQL Subnet**: 10.0.3.0/24 (delegated to MySQL Flexible Server)
- **Private DNS Zones**: Automatic DNS resolution for private endpoints

### Container Apps Configuration

- **Workload Profile**: Uses D4 dedicated workload profile (4 vCPU, 16 GB RAM per node)
- **Nginx Container**: Reverse proxy handling HTTP requests (1.0 CPU / 25%, 2 GB RAM / 12.5%)
- **PHP-FPM Container**: FastCGI PHP processor for WordPress (3.0 CPU / 75%, 6 GB RAM / 37.5%)
- **Total per replica**: 4 vCPU, 8 GB RAM (50% of D4 node capacity, allows 2 replicas per node)
- **Scaling**: 1-3 replicas based on concurrent requests (50 per replica threshold)
- **Note**: Resource combinations follow Azure Container Apps constraints (memory = 2x CPU)

### MySQL Configuration

- **Version**: MySQL 8.0 (latest in 8.0 series)
- **SKU**: Burstable B1ms (cost-effective for small/medium workloads)
- **Storage**: 20 GB with auto-grow enabled
- **Backup**: 7-day retention, geo-redundant disabled
- **Network**: Private access only through VNet integration

## Customization

### Change Container Images

To use custom WordPress or Nginx images, update the parameters:

```json
{
  "wordpressImage": {
    "value": "your-registry.azurecr.io/wordpress:custom"
  },
  "nginxImage": {
    "value": "your-registry.azurecr.io/nginx:custom"
  }
}
```

### Adjust Scaling

Edit the `scale` section in `main.bicep`:

```bicep
scale: {
  minReplicas: 2  // Minimum instances
  maxReplicas: 10 // Maximum instances
  rules: [
    {
      name: 'http-scaling'
      http: {
        metadata: {
          concurrentRequests: '100' // Requests per replica
        }
      }
    }
  ]
}
```

### Change MySQL SKU

For better performance, upgrade the MySQL SKU in `main.bicep`:

```bicep
sku: {
  name: 'Standard_D2ds_v4'  // General Purpose tier
  tier: 'GeneralPurpose'
}
```

## Monitoring

The deployment includes Log Analytics workspace integration:

```bash
# View logs for WordPress container app
az containerapp logs show \
  --name ca-wordpress-YOUR_ENV \
  --resource-group rg-wordpress-aca \
  --follow
```

## Security Considerations

1. **Passwords**: Use strong passwords and consider Azure Key Vault
2. **Network**: All backend services use private networking
3. **HTTPS**: Configure custom domain and certificate for HTTPS
4. **Updates**: Regularly update container images for security patches
5. **Firewall**: Consider adding Azure Firewall or NSG rules
6. **MySQL**: Enable SSL/TLS enforcement for MySQL connections

## Cost Optimization

- **Workload Profile**: D4 profile provides dedicated resources but has a cost
- **MySQL**: Start with Burstable tier, upgrade to General Purpose if needed
- **Storage**: Premium storage has higher cost but provides NFS support
- **Scaling**: Set appropriate min/max replicas to balance cost and performance

## Troubleshooting

### WordPress not accessible

1. Check Container App status:
   ```bash
   az containerapp show --name ca-wordpress-YOUR_ENV --resource-group rg-wordpress-aca
   ```

2. View container logs:
   ```bash
   az containerapp logs show --name ca-wordpress-YOUR_ENV --resource-group rg-wordpress-aca --follow
   ```

### NFS mount issues

1. Verify storage account private endpoint is correctly configured
2. Check that Container Apps subnet has connectivity to private endpoint subnet
3. Verify NFS share exists and is accessible

### Database connection errors

1. Verify MySQL server is running and accessible
2. Check MySQL credentials in container environment variables
3. Verify MySQL private DNS zone is linked to VNet

## Clean Up

To delete all resources:

```bash
az group delete --name rg-wordpress-aca --yes --no-wait
```

## Contributing

Feel free to submit issues and pull requests to improve this deployment template.

## License

This project is provided as-is for demonstration and learning purposes.

## [IMPORTANT!] Deployment notes

Some regions may not support all features (e.g., NFS on Premium Storage). Always check Azure documentation for regional availability before deploying.  
Furthermore others can have capacity constraints as for MySQL Flexible Server.  
Tests have been carried out in `norwayeast` region, which supports all features used in this deployment and does not have (as of now Feb 2026) MySQL Flexible Server capacity constraints.
