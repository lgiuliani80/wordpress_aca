# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with the WordPress on Azure Container Apps deployment.

## Pre-Deployment Issues

### Bicep Validation Fails

**Symptoms**: `az bicep build` command returns errors

**Solutions**:
1. Ensure you have the latest Azure CLI:
   ```bash
   az upgrade
   ```

2. Check Bicep version:
   ```bash
   az bicep version
   ```

3. Validate syntax:
   ```bash
   az bicep build --file main.bicep
   ```

### Parameter Validation Errors

**Symptoms**: Deployment fails with parameter validation error

**Common Issues**:
- MySQL password too short (minimum 8 characters)
- Password doesn't meet complexity requirements (need uppercase, lowercase, number, special character)
- Invalid location/region

**Solution**:
```bash
# Verify valid locations
az account list-locations --output table

# Use strong password
# Example: MyStr0ng!Pass
```

## Deployment Issues

### Deployment Timeout

**Symptoms**: Deployment takes very long or times out

**Cause**: Large deployments can take 15-20 minutes

**Solution**:
- Be patient; Container Apps and MySQL provisioning takes time
- Check deployment status:
  ```bash
  az deployment group show \
    --resource-group rg-wordpress-aca \
    --name <deployment-name>
  ```

### Subnet Address Space Conflicts

**Symptoms**: VNet or subnet creation fails

**Cause**: Address space conflicts with existing VNets

**Solution**:
- Modify the address spaces in `main.bicep`:
  ```bicep
  addressPrefixes: [
    '10.1.0.0/16'  // Change to available range
  ]
  ```

### MySQL Provisioning Fails

**Symptoms**: MySQL Flexible Server deployment fails

**Common Causes**:
1. Invalid credentials
2. Insufficient quota
3. Region doesn't support MySQL Flexible Server

**Solutions**:
```bash
# Check MySQL availability in region
az mysql flexible-server list-skus --location westeurope

# Verify subscription quota
az vm list-usage --location westeurope --output table
```

## Post-Deployment Issues

### WordPress Site Not Accessible

**Symptoms**: Cannot access WordPress URL returned by deployment

**Diagnostic Steps**:

1. **Check Container App status**:
   ```bash
   az containerapp show \
     --name ca-wordpress-YOUR_ENV \
     --resource-group rg-wordpress-aca \
     --query "properties.provisioningState"
   ```

2. **Verify ingress configuration**:
   ```bash
   az containerapp show \
     --name ca-wordpress-YOUR_ENV \
     --resource-group rg-wordpress-aca \
     --query "properties.configuration.ingress"
   ```

3. **Check container logs**:
   ```bash
   az containerapp logs show \
     --name ca-wordpress-YOUR_ENV \
     --resource-group rg-wordpress-aca \
     --tail 100
   ```

**Common Solutions**:
- Wait for initial WordPress setup (can take 2-3 minutes on first start)
- Check if containers are running
- Verify environment variables are set correctly

### Database Connection Errors

**Symptoms**: WordPress shows "Error establishing database connection"

**Diagnostic Steps**:

1. **Verify MySQL is running**:
   ```bash
   az mysql flexible-server show \
     --resource-group rg-wordpress-aca \
     --name mysql-YOUR_ENV-UNIQUE_ID \
     --query "state"
   ```

2. **Check private DNS zone**:
   ```bash
   az network private-dns zone show \
     --resource-group rg-wordpress-aca \
     --name privatelink.mysql.database.azure.com
   ```

3. **Verify VNet link**:
   ```bash
   az network private-dns link vnet list \
     --resource-group rg-wordpress-aca \
     --zone-name privatelink.mysql.database.azure.com
   ```

4. **Test database connectivity from Container App**:
   ```bash
   # Execute into the container
   az containerapp exec \
     --name ca-wordpress-YOUR_ENV \
     --resource-group rg-wordpress-aca \
     --container php-fpm \
     --command /bin/bash
   
   # Inside container, test MySQL connection
   mysql -h MYSQL_FQDN -u mysqladmin -p
   ```

**Common Solutions**:
- Verify MySQL credentials in Container App environment variables
- Check MySQL server firewall rules
- Ensure private DNS zone is properly linked

### Storage Mount Issues

**Symptoms**: WordPress can't write files, uploads fail

**Diagnostic Steps**:

1. **Check storage mount**:
   ```bash
   az containerapp show \
     --name ca-wordpress-YOUR_ENV \
     --resource-group rg-wordpress-aca \
     --query "properties.template.volumes"
   ```

2. **Verify storage account access**:
   ```bash
   az storage account show \
     --name stYOUR_ENV_UNIQUE_ID \
     --resource-group rg-wordpress-aca \
     --query "networkRuleSet"
   ```

3. **Check file share exists**:
   ```bash
   az storage share show \
     --account-name stYOUR_ENV_UNIQUE_ID \
     --name wordpress
   ```

4. **Test from within container**:
   ```bash
   # Exec into PHP-FPM container
   az containerapp exec \
     --name ca-wordpress-YOUR_ENV \
     --resource-group rg-wordpress-aca \
     --container php-fpm \
     --command /bin/bash
   
   # Check mount
   df -h | grep wordpress
   
   # Test write
   touch /var/www/html/test.txt
   ```

**Common Solutions**:
- Verify storage account key is correct
- Check VNet service endpoint or private endpoint configuration
- Ensure Container Apps subnet has access to storage account
- Verify file share is created

### Performance Issues

**Symptoms**: WordPress is slow, pages take long to load

**Diagnostic Steps**:

1. **Check container resource usage**:
   ```bash
   az containerapp logs show \
     --name ca-wordpress-YOUR_ENV \
     --resource-group rg-wordpress-aca \
     --type system \
     --tail 50
   ```

2. **Monitor metrics**:
   ```bash
   # View in Azure Portal
   # Navigate to Container App → Monitoring → Metrics
   # Check: CPU, Memory, HTTP Request Duration
   ```

3. **Check MySQL performance**:
   ```bash
   # Navigate to MySQL server → Monitoring → Metrics
   # Check: CPU percent, Memory percent, Active connections
   ```

**Common Solutions**:
- Increase container resources in `main.bicep`
- Upgrade MySQL SKU to higher tier
- Add more replicas (increase maxReplicas)
- Consider adding Redis for caching
- Optimize WordPress plugins

### Scaling Issues

**Symptoms**: Container App doesn't scale as expected

**Diagnostic Steps**:

1. **Check current replica count**:
   ```bash
   az containerapp revision show \
     --name ca-wordpress-YOUR_ENV \
     --resource-group rg-wordpress-aca \
     --query "properties.replicas"
   ```

2. **View scaling rules**:
   ```bash
   az containerapp show \
     --name ca-wordpress-YOUR_ENV \
     --resource-group rg-wordpress-aca \
     --query "properties.template.scale"
   ```

3. **Check scaling events**:
   ```bash
   az monitor activity-log list \
     --resource-group rg-wordpress-aca \
     --max-events 20
   ```

**Common Solutions**:
- Adjust scaling thresholds in `main.bicep`
- Ensure workload profile has available capacity
- Check for resource quotas

## Debugging Commands

### View All Container Logs
```bash
az containerapp logs show \
  --name ca-wordpress-YOUR_ENV \
  --resource-group rg-wordpress-aca \
  --follow
```

### View Nginx Logs Only
```bash
az containerapp logs show \
  --name ca-wordpress-YOUR_ENV \
  --resource-group rg-wordpress-aca \
  --container nginx \
  --tail 50
```

### View PHP-FPM Logs Only
```bash
az containerapp logs show \
  --name ca-wordpress-YOUR_ENV \
  --resource-group rg-wordpress-aca \
  --container php-fpm \
  --tail 50
```

### Execute Commands in Container
```bash
# Execute in PHP-FPM container
az containerapp exec \
  --name ca-wordpress-YOUR_ENV \
  --resource-group rg-wordpress-aca \
  --container php-fpm \
  --command /bin/bash

# Execute in Nginx container
az containerapp exec \
  --name ca-wordpress-YOUR_ENV \
  --resource-group rg-wordpress-aca \
  --container nginx \
  --command /bin/sh
```

### Check Private Endpoint Status
```bash
az network private-endpoint show \
  --resource-group rg-wordpress-aca \
  --name pe-stYOUR_ENV_UNIQUE_ID \
  --query "customDnsConfigs"
```

### View MySQL Logs
```bash
az mysql flexible-server server-logs list \
  --resource-group rg-wordpress-aca \
  --server-name mysql-YOUR_ENV-UNIQUE_ID
```

## Common WordPress-Specific Issues

### White Screen of Death (WSOD)

**Cause**: PHP error, plugin conflict, or theme issue

**Solution**:
1. Enable WordPress debug mode
2. Check PHP-FPM logs for errors
3. Disable plugins via database:
   ```sql
   UPDATE wp_options SET option_value = '' 
   WHERE option_name = 'active_plugins';
   ```

### Upload Limit Issues

**Cause**: PHP or Nginx upload size limits

**Solution**: Modify `nginx.conf`:
```nginx
client_max_body_size 100M;  # Increase as needed
```

Then update Container App with new configuration.

### Permalink Issues

**Cause**: .htaccess not working (Nginx doesn't use .htaccess)

**Solution**: Permalinks are already configured in `nginx.conf`:
```nginx
location / {
    try_files $uri $uri/ /index.php?$args;
}
```

## Getting Help

If you're still experiencing issues:

1. **Check Azure Service Health**: [status.azure.com](https://status.azure.com)
2. **Review Azure Documentation**: [docs.microsoft.com/azure](https://docs.microsoft.com/azure)
3. **Azure Support**: Open a support ticket in Azure Portal
4. **Community Forums**: 
   - Stack Overflow (tag: azure-container-apps)
   - Microsoft Q&A

## Useful Log Queries

### Query Log Analytics

```kusto
// Container App logs
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "ca-wordpress-YOUR_ENV"
| order by TimeGenerated desc
| take 100

// System logs
ContainerAppSystemLogs_CL
| where ContainerAppName_s == "ca-wordpress-YOUR_ENV"
| where Level_s == "Error"
| order by TimeGenerated desc
| take 50
```

### MySQL Slow Query Log

```bash
# Enable slow query log
az mysql flexible-server parameter set \
  --resource-group rg-wordpress-aca \
  --server-name mysql-YOUR_ENV-UNIQUE_ID \
  --name slow_query_log \
  --value ON
```

## Best Practices for Troubleshooting

1. **Always check logs first** - Most issues are logged
2. **Use --output table** for readable Azure CLI output
3. **Enable debug mode** temporarily when troubleshooting
4. **Document your changes** - Keep track of what you've modified
5. **Test in dev environment first** - Don't troubleshoot in production
6. **Use version control** - Keep your Bicep files in Git
7. **Monitor metrics** - Set up alerts before issues occur
