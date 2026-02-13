// WordPress on Azure Container Apps with NFS Storage and Private Networking
// This template deploys a complete WordPress solution on Container Apps

@description('The name of the environment')
param environmentName string

@description('The location for all resources')
param location string = resourceGroup().location

@description('MySQL admin username')
@secure()
param mysqlAdminUser string

@description('MySQL admin password')
@secure()
param mysqlAdminPassword string

@description('WordPress database name')
param wordpressDbName string = 'wordpress'

@description('Container image for WordPress/PHP-FPM')
param wordpressImage string = 'wordpress:php8.2-fpm'

@description('Container image for Nginx')
param nginxImage string = 'nginx:alpine'

@description('Name of the Website')
param sitename string = 'wpsite'

@description('Allowed IP address to whitelist for Storage Account access')
param allowedIpAddress string = ''


// Variables
var uniqueSuffix = take(uniqueString(resourceGroup().id),4)
var storageAccountName = 'st${environmentName}${uniqueSuffix}'
var mysqlServerName = 'mysql-${environmentName}-${uniqueSuffix}'
var redisName = 'redis-${environmentName}-${uniqueSuffix}'
var vnetName = 'vnet-${environmentName}'
var containerAppEnvName = 'cae-${environmentName}'
var wordpressAppName = 'ca-${sitename}-${environmentName}'

// Virtual Network for private networking
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'container-apps-subnet'
        properties: {
          addressPrefix: '10.0.0.0/23'
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'private-endpoints-subnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'mysql-subnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
          delegations: [
            {
              name: 'Microsoft.DBforMySQL.flexibleServers'
              properties: {
                serviceName: 'Microsoft.DBforMySQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

// Storage Account with Premium tier for NFS support
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  tags: {
    SecurityControl: 'Ignore'
  }
  sku: {
    name: 'PremiumV2_LRS'
  }
  kind: 'FileStorage'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    azureFilesIdentityBasedAuthentication: {
      smbOAuthSettings: {
        isSmbOAuthEnabled: false
      }
      directoryServiceOptions: 'None'
    }
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    largeFileSharesState: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: !empty(allowedIpAddress) ? [
        {
          value: allowedIpAddress
          action: 'Allow'
        }
      ] : []
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: false
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

resource files_default 'Microsoft.Storage/storageAccounts/fileServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    protocolSettings: {
      smb: {
        multichannel: {
          enabled: true
        }
      }
    }
    cors: {
      corsRules: []
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// NFS File Share for WordPress files
resource wordpressNfsShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: files_default
  name: 'wordpress'
  properties: {
    enabledProtocols: 'NFS'
  }
}

// NFS File Share for Nginx configuration
resource nginxConfigNfsShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: files_default
  name: 'nginx-config'
  properties: {
    enabledProtocols: 'NFS'
  }
}

// Private DNS Zone for Storage Account
resource storagePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.file.${environment().suffixes.storage}'
  location: 'global'
}

// Link Private DNS Zone to VNet
resource storagePrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: storagePrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Private Endpoint for Storage Account
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: 'pe-${storageAccountName}'
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id // private-endpoints-subnet
    }
    privateLinkServiceConnections: [
      {
        name: 'storage-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone Group for Storage
resource storagePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: storagePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: storagePrivateDnsZone.id
        }
      }
    ]
  }
}

// Private DNS Zone for MySQL
resource mysqlPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.mysql.database.azure.com'
  location: 'global'
}

// Link MySQL Private DNS Zone to VNet
resource mysqlPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: mysqlPrivateDnsZone
  name: '${vnetName}-mysql-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// MySQL Flexible Server
resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2021-05-01' = {
  name: mysqlServerName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    createMode: 'Default'
    version: '8.0.21'
    administratorLogin: mysqlAdminUser
    administratorLoginPassword: mysqlAdminPassword
    storage: {
      storageSizeGB: 20
    }
    network: {
      delegatedSubnetResourceId: vnet.properties.subnets[2].id // mysql-subnet
      privateDnsZoneResourceId: mysqlPrivateDnsZone.id
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    availabilityZone: ''
    highAvailability: {
      mode: 'Disabled'
    }
  }
  dependsOn: [
    mysqlPrivateDnsZoneLink
  ]
}


// MySQL Database
resource mysqlDatabase 'Microsoft.DBforMySQL/flexibleServers/databases@2021-05-01' = {
  parent: mysqlServer
  name: wordpressDbName
  properties: {
    charset: 'utf8mb4'
    collation: 'utf8mb4_unicode_ci'
  }
}

// Azure Managed Redis (Redis Enterprise) for session caching
resource redisEnterprise 'Microsoft.Cache/redisEnterprise@2025-07-01' = {
  name: redisName
  location: location
  tags: {
    SecurityControl: 'Ignore'
  }
  sku: {
    name: 'Balanced_B5'
  }
  identity: {
    type: 'None'
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
  }
}

// Redis Enterprise Database with non-clustered policy
resource redisEnterpriseDatabase 'Microsoft.Cache/redisEnterprise/databases@2025-07-01' = {
  name: 'default'
  parent: redisEnterprise
  properties: {
    clientProtocol: 'Plaintext'
    port: 10000
    clusteringPolicy: 'NoCluster'
    evictionPolicy: 'VolatileLRU'
    accessKeysAuthentication: 'Enabled'
    persistence: {
      aofEnabled: false
      rdbEnabled: false
    }
  }
}

// Private DNS Zone for Redis Enterprise
resource redisPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.redis.azure.net'
  location: 'global'
}

// Link Redis Private DNS Zone to VNet
resource redisPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: redisPrivateDnsZone
  name: '${vnetName}-redis-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Private Endpoint for Redis Enterprise
resource redisPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: 'pe-${redisName}'
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id // private-endpoints-subnet
    }
    privateLinkServiceConnections: [
      {
        name: 'redis-connection'
        properties: {
          privateLinkServiceId: redisEnterprise.id
          groupIds: [
            'redisEnterprise'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone Group for Redis
resource redisPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: redisPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: redisPrivateDnsZone.id
        }
      }
    ]
  }
}

// Log Analytics Workspace for Container Apps
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${environmentName}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Container Apps Environment with Workload Profile
resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: vnet.properties.subnets[0].id // container-apps-subnet
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
      {
        name: 'D4'
        workloadProfileType: 'D4'
        minimumCount: 1
        maximumCount: 3
      }
    ]
  }
}

// NFS-enabled managed storage for Container Apps Environment
// These storages use Premium FileStorage with NFS 4.1 protocol
// Using nfsAzureFile property for true NFS mounting
// Note: Bicep type definitions may show a warning, but this is the correct property per Azure docs
resource nginxConfigNfsStorage 'Microsoft.App/managedEnvironments/storages@2025-02-02-preview' = {
  parent: containerAppEnv
  name: 'nginx-config-nfs-storage'
  properties: {
    nfsAzureFile: {
      server: '${storageAccountName}.file.${environment().suffixes.storage}'
      shareName: '/${storageAccountName}/nginx-config'
      accessMode: 'ReadOnly'
    }
  }
  dependsOn: [
    nginxConfigNfsShare
    storagePrivateEndpoint
    storagePrivateDnsZoneGroup
  ]
}

resource wordpressNfsStorage 'Microsoft.App/managedEnvironments/storages@2025-02-02-preview' = {
  parent: containerAppEnv
  name: 'wordpress-nfs-storage'
  properties: {
    nfsAzureFile: {
      server: '${storageAccountName}.file.${environment().suffixes.storage}'
      shareName: '/${storageAccountName}/wordpress'
      accessMode: 'ReadWrite'
    }
  }
  dependsOn: [
    wordpressNfsShare
    storagePrivateEndpoint
    storagePrivateDnsZoneGroup
  ]
}

// WordPress Container App with Nginx + PHP-FPM
// WordPress files and nginx config are mounted via NFS-enabled Azure Files
resource wordpressApp 'Microsoft.App/containerApps@2024-02-02-preview' = {
  name: wordpressAppName
  location: location
  properties: {
    managedEnvironmentId: containerAppEnv.id
    workloadProfileName: 'D4'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        transport: 'http'
        allowInsecure: false
        stickySessions: {
          affinity: 'sticky' // TODO: this can be removed if the backing of sessions is done via Redis or similar, but for simplicity we use in-memory session handling in this example, which requires sticky sessions to work properly
        }
      }
      secrets: [
        {
          name: 'mysql-password'
          value: mysqlAdminPassword
        }
        {
          name: 'redis-password'
          value: redisEnterpriseDatabase.listKeys().primaryKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'nginx'
          image: nginxImage
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          volumeMounts: [
            {
              volumeName: 'wordpress-files'
              mountPath: '/var/www/html'
            }
            {
              volumeName: 'nginx-config'
              mountPath: '/etc/nginx'
            }
          ]
        }
        {
          name: 'php-fpm'
          image: wordpressImage
          resources: {
            cpu: json('3.0')
            memory: '6Gi'
          }
          env: [
            {
              name: 'WORDPRESS_DB_HOST'
              value: mysqlServer.properties.fullyQualifiedDomainName
            }
            {
              name: 'WORDPRESS_DB_USER'
              value: mysqlAdminUser
            }
            {
              name: 'WORDPRESS_DB_PASSWORD'
              secretRef: 'mysql-password'
            }
            {
              name: 'WORDPRESS_DB_NAME'
              value: wordpressDbName
            }
            {
              name: 'WORDPRESS_CONFIG_EXTRA'
              value: 'define(\'FS_METHOD\', \'direct\');'
            }
            {
              name: 'REDIS_HOST'
              value: '${redisName}.${location}.redis.azure.net:10000'
            }
            {
              name: 'REDIS_PASSWORD'
              secretRef: 'redis-password'
            }
          ]
          volumeMounts: [
            {
              volumeName: 'wordpress-files'
              mountPath: '/var/www/html'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
      volumes: [
        {
          name: 'wordpress-files'
          storageName: 'wordpress-nfs-storage'
          storageType: 'NfsAzureFile'
        }
        {
          name: 'nginx-config'
          storageName: 'nginx-config-nfs-storage'
          storageType: 'NfsAzureFile'
        }
      ]
    }
  }
  dependsOn: [
    wordpressNfsStorage
    nginxConfigNfsStorage
    mysqlDatabase
    redisPrivateDnsZoneGroup
  ]
}

// Outputs
output wordpressUrl string = 'https://${wordpressApp.properties.configuration.ingress.fqdn}'
output storageAccountName string = storageAccount.name
output mysqlServerFqdn string = mysqlServer.properties.fullyQualifiedDomainName
output containerAppEnvId string = containerAppEnv.id
output redisHostName string = '${redisName}.${location}.redis.azure.net'
