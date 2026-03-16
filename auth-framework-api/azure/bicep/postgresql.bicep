@description('Resource prefix for naming')
param resourcePrefix string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('Deployment environment')
param environment string

@description('PostgreSQL admin password')
@secure()
param dbPassword string

@description('Delegated subnet ID for PostgreSQL')
param subnetId string

@description('Private DNS zone ID for PostgreSQL')
param privateDnsZoneId string

@description('PostgreSQL SKU name')
param skuName string = 'Standard_D2s_v3'

@description('PostgreSQL storage in GB')
param storageSizeGb int = 32

@description('PostgreSQL version')
param postgresVersion string = '16'

var serverName = '${resourcePrefix}-psql'
var isProduction = environment == 'prod'

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: startsWith(skuName, 'B_') ? 'Burstable' : startsWith(skuName, 'GP_') ? 'GeneralPurpose' : 'MemoryOptimized'
  }
  properties: {
    administratorLogin: 'psqladmin'
    administratorLoginPassword: dbPassword
    version: postgresVersion
    storage: {
      storageSizeGB: storageSizeGb
    }
    backup: {
      backupRetentionDays: 35
      geoRedundantBackup: isProduction ? 'Enabled' : 'Disabled'
    }
    highAvailability: isProduction ? {
      mode: 'ZoneRedundant'
      standbyAvailabilityZone: '2'
    } : {
      mode: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: subnetId
      privateDnsZoneArmResourceId: privateDnsZoneId
    }
    maintenanceWindow: {
      customWindow: 'Enabled'
      dayOfWeek: 0
      startHour: 2
      startMinute: 0
    }
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-03-01-preview' = {
  parent: postgresServer
  name: 'authframework'
  properties: {
    charset: 'utf8'
    collation: 'en_US.utf8'
  }
}

resource sslConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-03-01-preview' = {
  parent: postgresServer
  name: 'require_secure_transport'
  properties: {
    value: 'on'
    source: 'user-override'
  }
}

resource logConnectionsConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-03-01-preview' = {
  parent: postgresServer
  name: 'log_connections'
  properties: {
    value: 'on'
    source: 'user-override'
  }
}

resource firewallAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-03-01-preview' = {
  parent: postgresServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output postgresqlFqdn string = postgresServer.properties.fullyQualifiedDomainName
output postgresqlServerName string = postgresServer.name
output postgresqlServerId string = postgresServer.id
