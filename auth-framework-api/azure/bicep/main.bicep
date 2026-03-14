@description('Deployment environment')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Project name prefix for all resources')
param projectName string = 'authframework'

@description('PostgreSQL administrator password')
@secure()
param dbPassword string

@description('JWT secret key')
@secure()
param jwtSecretKey string

@description('Data encryption key')
@secure()
param encryptionKey string

@description('Alert notification email')
param alertEmail string = 'ops@example.com'

@description('App Service SKU name')
param appServiceSkuName string = 'B2'

@description('PostgreSQL SKU name')
param postgresqlSkuName string = 'Standard_D2s_v3'

@description('Container image tag to deploy')
param imageTag string = 'latest'

var resourcePrefix = '${projectName}-${environment}'
var commonTags = {
  Environment: environment
  Project: projectName
  ManagedBy: 'Bicep'
}

module networking 'networking.bicep' = {
  name: 'networkingDeployment'
  params: {
    resourcePrefix: resourcePrefix
    location: location
    tags: commonTags
  }
}

module monitoring 'monitoring.bicep' = {
  name: 'monitoringDeployment'
  params: {
    resourcePrefix: resourcePrefix
    location: location
    tags: commonTags
    alertEmail: alertEmail
  }
}

module keyVault 'key_vault.bicep' = {
  name: 'keyVaultDeployment'
  params: {
    resourcePrefix: resourcePrefix
    location: location
    tags: commonTags
    dbPassword: dbPassword
    jwtSecretKey: jwtSecretKey
    encryptionKey: encryptionKey
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
  }
}

module postgresql 'postgresql.bicep' = {
  name: 'postgresqlDeployment'
  params: {
    resourcePrefix: resourcePrefix
    location: location
    tags: commonTags
    environment: environment
    dbPassword: dbPassword
    subnetId: networking.outputs.dbSubnetId
    privateDnsZoneId: networking.outputs.postgresPrivateDnsZoneId
  }
}

module appService 'app_service.bicep' = {
  name: 'appServiceDeployment'
  params: {
    resourcePrefix: resourcePrefix
    location: location
    tags: commonTags
    environment: environment
    keyVaultName: keyVault.outputs.keyVaultName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    subnetId: networking.outputs.appSubnetId
    imageTag: imageTag
    appServiceSkuName: appServiceSkuName
  }
  dependsOn: [keyVault, monitoring]
}

output appServiceUrl string = appService.outputs.appServiceUrl
output postgresqlFqdn string = postgresql.outputs.postgresqlFqdn
output keyVaultUri string = keyVault.outputs.keyVaultUri
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
