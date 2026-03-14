@description('Resource prefix for naming')
param resourcePrefix string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('Deployment environment')
param environment string

@description('Key Vault name for secret references')
param keyVaultName string

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('VNet subnet ID for VNet integration')
param subnetId string

@description('Container image tag')
param imageTag string = 'latest'

@description('App Service Plan SKU')
param appServiceSkuName string = 'B2'

var appName = '${resourcePrefix}-api'
var planName = '${resourcePrefix}-asp'
var isProduction = environment == 'prod'

resource servicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: appServiceSkuName
  }
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: appName
  location: location
  tags: tags
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: servicePlan.id
    httpsOnly: true
    siteConfig: {
      alwaysOn: true
      healthCheckPath: '/health'
      linuxFxVersion: 'DOCKER|${appName}acr.azurecr.io/authframework-api:${imageTag}'
      appSettings: [
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: isProduction ? 'Production' : 'Staging'
        }
        {
          name: 'ASPNETCORE_URLS'
          value: 'http://+:8080'
        }
        {
          name: 'WEBSITES_PORT'
          value: '8080'
        }
        {
          name: 'ConnectionStrings__DefaultConnection'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=db-connection-string)'
        }
        {
          name: 'JwtSettings__SecretKey'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=jwt-secret-key)'
        }
        {
          name: 'JwtSettings__Issuer'
          value: 'https://${appName}.azurewebsites.net'
        }
        {
          name: 'JwtSettings__Audience'
          value: 'authframework-api'
        }
        {
          name: 'JwtSettings__ExpiryMinutes'
          value: isProduction ? '30' : '60'
        }
        {
          name: 'EncryptionSettings__Key'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=encryption-key)'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
      ]
    }
    virtualNetworkSubnetId: subnetId
    vnetRouteAllEnabled: true
  }
}

resource stagingSlot 'Microsoft.Web/sites/slots@2023-01-01' = {
  parent: webApp
  name: 'staging'
  location: location
  tags: tags
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: servicePlan.id
    httpsOnly: true
    siteConfig: {
      alwaysOn: false
      healthCheckPath: '/health'
      linuxFxVersion: 'DOCKER|${appName}acr.azurecr.io/authframework-api:${imageTag}'
      appSettings: [
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Staging'
        }
        {
          name: 'ASPNETCORE_URLS'
          value: 'http://+:8080'
        }
        {
          name: 'WEBSITES_PORT'
          value: '8080'
        }
        {
          name: 'ConnectionStrings__DefaultConnection'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=db-connection-string)'
        }
        {
          name: 'JwtSettings__SecretKey'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=jwt-secret-key)'
        }
        {
          name: 'JwtSettings__Issuer'
          value: 'https://${appName}-staging.azurewebsites.net'
        }
        {
          name: 'JwtSettings__Audience'
          value: 'authframework-api'
        }
        {
          name: 'EncryptionSettings__Key'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=encryption-key)'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
      ]
    }
  }
}

output appServiceUrl string = 'https://${webApp.properties.defaultHostName}'
output appServiceName string = webApp.name
output appServicePrincipalId string = webApp.identity.principalId
output stagingSlotPrincipalId string = stagingSlot.identity.principalId
output stagingSlotUrl string = 'https://${stagingSlot.properties.defaultHostName}'
