# Architecture Overview

> **Deployment**: This solution can be deployed using [Azure Developer CLI (azd)](./AZD_GUIDE.md) for a streamlined experience with automatic parameter validation.

## Component Details

### 1. Virtual Network (10.0.0.0/16)

The solution uses a dedicated VNet with three subnets for network isolation:

- **Container Apps Subnet (10.0.0.0/23)**: Delegated to `Microsoft.App/environments`
- **Private Endpoints Subnet (10.0.2.0/24)**: Hosts private endpoints for Storage Account and Redis Enterprise
- **MySQL Subnet (10.0.3.0/24)**: Delegated to `Microsoft.DBforMySQL/flexibleServers`

### 2. Storage Account (Premium FileStorage)

- **SKU**: Premium_LRS (locally redundant storage)
- **Kind**: FileStorage (optimized for file shares)
- **Protocol**: NFS 4.1 (enabled for both shares)
- **Network**: Private endpoint with dedicated private DNS zone
- **Shares**: 
  - `wordpress`: WordPress files mounted at `/var/www/html` (NFS 4.1)
  - `nginx-config`: Nginx configuration mounted at `/etc/nginx` (NFS 4.1)

**Note**: Premium FileStorage with NFS 4.1 protocol enabled provides true NFS mounting for WordPress files and nginx configuration. The postprovision hook automatically uploads nginx.conf to the NFS share after infrastructure provisioning.

### 3. MySQL Flexible Server

- **Version**: MySQL 8.0 (latest in 8.0 series)
- **SKU**: Standard_B1ms (Burstable tier)
  - 1 vCore
  - 2 GB RAM
  - Cost-effective for small/medium workloads
- **Storage**: 20 GB with auto-grow enabled
- **Backup**: 7-day retention
- **Network**: VNet integrated (private access only)
- **Character Set**: utf8mb4 with utf8mb4_unicode_ci collation

### 4. Redis Enterprise

- **Purpose**: Session caching and object caching for WordPress
- **SKU**: Balanced_B5 (balanced performance tier)
- **Network**: Private endpoint with dedicated private DNS zone (privatelink.redis.azure.net)
- **Security**: 
  - Public network access disabled
  - TLS 1.2 minimum version
  - Access key authentication enabled
- **Database Configuration**:
  - Port: 10000
  - Client Protocol: Plaintext
  - Clustering Policy: NoCluster (single shard)
  - Eviction Policy: VolatileLRU (volatile keys with least recently used eviction)
  - Persistence: Disabled (AOF and RDB both disabled for performance)
- **Private Connectivity**: Accessible only through private endpoint in VNet

**Note**: Redis Enterprise provides enterprise-grade caching with high availability and performance for WordPress session management and object caching.

### 5. Container Apps Environment

- **Type**: Workload Profile-based environment
- **VNet Integration**: Uses dedicated subnet
- **Logging**: Log Analytics workspace integration
- **Workload Profiles**:
  - **Consumption**: Default profile for system workloads
  - **D4**: Dedicated profile for WordPress (4 vCPU, 16 GB RAM per node)

### 6. WordPress Container App

The WordPress application runs as a multi-container app with:

#### Nginx Container
- **Image**: nginx:alpine
- **Resources**: 1.0 CPU (25% of D4), 2 GB RAM (12.5% of D4)
- **Role**: Reverse proxy, static content serving
- **Port**: 80 (HTTP)
- **Mounts**: 
  - `/var/www/html`: WordPress files (NFS 4.1)
  - `/etc/nginx`: Nginx configuration (NFS 4.1)
- **Features**:
  - FastCGI pass-through to PHP-FPM
  - Static content caching
  - Gzip compression
  - Request buffering

#### PHP-FPM Container
- **Image**: wordpress:php8.2-fpm
- **Resources**: 3.0 CPU (75% of D4), 6 GB RAM (37.5% of D4)
- **Role**: PHP application server
- **Mounts**:
  - `/var/www/html`: WordPress files (NFS 4.1)
- **Environment Variables**:
  - `WORDPRESS_DB_HOST`: MySQL server FQDN
  - `WORDPRESS_DB_USER`: MySQL username
  - `WORDPRESS_DB_PASSWORD`: From secrets
  - `WORDPRESS_DB_NAME`: Database name
  - `WORDPRESS_CONFIG_EXTRA`: Additional WP config

#### Resource Allocation Notes
- **Total per replica**: 4 vCPU, 8 GB RAM (50% of D4 node capacity)
- **Valid combinations**: Azure Container Apps requires memory = 2x CPU (0.25/0.5, 0.5/1, 1/2, 2/4, 3/6, 4/8)
- **Capacity**: D4 node can run 2 replicas (8 vCPU / 16 GB total per node)

#### Scaling Configuration
- **Min Replicas**: 1
- **Max Replicas**: 3
- **Scaling Rule**: HTTP-based
  - Trigger: 50 concurrent requests per replica
  - Scale-out when concurrent requests exceed threshold
  - Scale-in when traffic decreases

## Data Flow

### HTTP Request Flow
```
1. Client Request
   ↓
2. Container Apps Ingress (HTTPS/HTTP)
   ↓
3. Nginx Container (Port 80)
   ↓
4. Static content? → Serve directly from NFS share
   ↓
5. PHP request? → Forward to PHP-FPM via FastCGI (Port 9000)
   ↓
6. PHP-FPM processes WordPress
   ↓
7. Database query? → Connect to MySQL (Private Network)
   ↓
8. Response back through chain
```

### File Storage Flow
```
1. WordPress writes/reads files
   ↓
2. PHP-FPM accesses /var/www/html
   ↓
3. Azure Files SMB mount
   ↓
4. Private Endpoint
   ↓
5. Premium Storage Account
```

### Database Flow
```
1. WordPress needs data
   ↓
2. PHP-FPM MySQL client
   ↓
3. Private DNS resolution
   ↓
4. VNet routing to MySQL subnet
   ↓
5. MySQL Flexible Server
```

## Security Architecture

### Network Security Layers

1. **Public Internet** → Only Container Apps Ingress is publicly accessible
2. **Container Apps Environment** → Isolated in dedicated VNet subnet
3. **Storage Account** → Only accessible via private endpoint
4. **MySQL Server** → Only accessible via VNet integration (no public endpoint)

### Private DNS Zones

- `privatelink.file.{environment.suffixes.storage}`: For Storage Account
- `privatelink.mysql.database.azure.com`: For MySQL Server

Both zones are linked to the VNet for automatic name resolution.

## High Availability

### Container Apps
- Multiple replicas across availability zones (when available)
- Automatic health checks and restarts
- Rolling updates with zero downtime

### Storage
- Premium_LRS provides local redundancy
- Multiple copies within same datacenter
- High IOPS and throughput

### MySQL
- Burstable tier with automatic backups
- 7-day point-in-time restore
- Can upgrade to zone-redundant HA if needed

## Performance Considerations

### Storage
- **Premium FileStorage**: Designed for low-latency workloads
- **IOPS**: Up to 100,000 IOPS per storage account
- **Throughput**: Up to 10 GB/s

### Compute
- **Workload Profile D4**: Dedicated resources, no noisy neighbors
- **Nginx**: Lightweight, efficient static file serving
- **PHP-FPM**: Optimized PHP execution

### Database
- **Burstable B1ms**: Suitable for small/medium sites
- **Burst Credits**: Handle traffic spikes
- **Upgrade Path**: Can scale to General Purpose or Memory Optimized tiers

## Cost Optimization Tips

1. **Start Small**: Use B1ms MySQL and D4 workload profile initially
2. **Scale Database**: Upgrade MySQL only when needed
3. **Adjust Replicas**: Set min replicas to 1 for dev/test environments
4. **Monitor Usage**: Use Azure Monitor to identify optimization opportunities
5. **Reserved Capacity**: Consider reserved instances for production workloads

## Disaster Recovery

### Backup Strategy
- **MySQL**: Automated backups (7-day retention)
- **Storage**: Point-in-time restore capability
- **Container Images**: Store in Azure Container Registry with geo-replication

### Recovery Steps
1. Restore MySQL from backup
2. Redeploy Bicep template
3. Mount existing storage account
4. Update DNS if needed

## Monitoring and Observability

### Built-in Monitoring
- **Log Analytics**: Container logs and metrics
- **Application Insights**: Can be added for deeper APM
- **Azure Monitor**: Resource health and alerts

### Key Metrics to Monitor
- Container App CPU/Memory usage
- HTTP request latency and error rates
- MySQL connections and query performance
- Storage IOPS and throughput
- Scaling events

## Limitations and Considerations

1. **NFS Support**: While Premium FileStorage supports NFS, Container Apps uses SMB for managed mounts
2. **SSL/TLS**: Configure custom domain and certificates for production HTTPS
3. **WordPress Plugins**: Some plugins may have compatibility issues with shared storage
4. **Session Affinity**: Enabled (sticky) by default; set `PHP_SESSIONS_IN_REDIS=true` to use Redis for session storage and disable sticky sessions
5. **File Upload Size**: Limited by Nginx configuration (default 100MB)

## Future Enhancements

1. Add Azure Front Door for global load balancing
2. Implement Azure CDN for static content delivery
3. ~~Add Redis for object caching and session storage~~ — Done: set `PHP_SESSIONS_IN_REDIS=true`
4. Configure custom domain with managed certificate
5. Enable Azure WAF for additional security
6. Implement backup automation for WordPress files
7. Add monitoring dashboards and alerts
