@description('Resource prefix for naming')
param resourcePrefix string

@description('Azure region')
param location string

@description('Resource tags')
param tags object

@description('Alert notification email')
param alertEmail string = 'ops@example.com'

@description('Log retention in days')
param logRetentionDays int = 30

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${resourcePrefix}-law'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${resourcePrefix}-ai'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${resourcePrefix}-ag'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'authfwag'
    enabled: true
    emailReceivers: [
      {
        name: 'ops-team'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output actionGroupId string = actionGroup.id
