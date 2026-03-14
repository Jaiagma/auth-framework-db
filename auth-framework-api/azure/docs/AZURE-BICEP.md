# Azure Bicep Templates Guide

This guide covers the Bicep infrastructure-as-code templates provided as an alternative to
Terraform for teams that prefer ARM-native tooling.

---

## Table of Contents

1. [Module Structure](#module-structure)
2. [Deployment Commands](#deployment-commands)
3. [Parameter File Usage](#parameter-file-usage)
4. [What-If Deployments](#what-if-deployments)
5. [Bicep vs Terraform Comparison](#bicep-vs-terraform-comparison)

---

## Module Structure

```
bicep/
├── main.bicep                    # Root template — orchestrates all modules
├── main.bicepparam               # Root parameter file (Bicep params format)
│
├── modules/
│   ├── networking.bicep          # VNet, subnets, NSGs, private DNS zones
│   ├── app-service.bicep         # App Service Plan, Web App, slots, autoscale
│   ├── postgresql.bicep          # PostgreSQL Flexible Server, database, config
│   ├── key-vault.bicep           # Key Vault, access policies, private endpoint
│   ├── acr.bicep                 # Container Registry, geo-replication
│   └── monitoring.bicep          # Log Analytics, App Insights, alerts
│
└── parameters/
    ├── dev.bicepparam
    ├── staging.bicepparam
    └── prod.bicepparam
```

### Root Template (`main.bicep`)

The root template wires all modules together and passes outputs between them:

```bicep
targetScope = 'resourceGroup'

param environment string
param location string = resourceGroup().location
param appName string = 'auth-framework'

// Networking must be deployed first — other modules depend on subnet IDs
module networking 'modules/networking.bicep' = {
  name: 'networking'
  params: {
    environment: environment
    location: location
    appName: appName
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'key-vault'
  params: {
    environment: environment
    location: location
    appName: appName
    peSubnetId: networking.outputs.peSubnetId
    privateDnsZoneId: networking.outputs.keyVaultPrivateDnsZoneId
  }
}

module acr 'modules/acr.bicep' = {
  name: 'acr'
  params: {
    environment: environment
    location: location
    appName: appName
    peSubnetId: networking.outputs.peSubnetId
    privateDnsZoneId: networking.outputs.acrPrivateDnsZoneId
  }
}

module postgresql 'modules/postgresql.bicep' = {
  name: 'postgresql'
  params: {
    environment: environment
    location: location
    appName: appName
    delegatedSubnetId: networking.outputs.dataSubnetId
    privateDnsZoneId: networking.outputs.postgresPrivateDnsZoneId
    keyVaultName: keyVault.outputs.keyVaultName
  }
}

module appService 'modules/app-service.bicep' = {
  name: 'app-service'
  params: {
    environment: environment
    location: location
    appName: appName
    appSubnetId: networking.outputs.appSubnetId
    acrLoginServer: acr.outputs.loginServer
    keyVaultUri: keyVault.outputs.uri
    appInsightsConnectionString: monitoring.outputs.connectionString
  }
  dependsOn: [acr, keyVault, postgresql]
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    environment: environment
    location: location
    appName: appName
    appServiceResourceId: appService.outputs.resourceId
  }
}
```

### App Service Module (`modules/app-service.bicep`)

```bicep
param environment string
param location string
param appName string
param appSubnetId string
param acrLoginServer string
param keyVaultUri string
param appInsightsConnectionString string
param skuName string = environment == 'prod' ? 'P1v3' : 'B2'

var appServicePlanName = 'asp-${appName}-${environment}'
var webAppName = 'app-${appName}-${environment}'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  sku: {
    name: skuName
  }
  properties: {
    reserved: true  // Required for Linux
  }
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acrLoginServer}/auth-framework-api:latest'
      alwaysOn: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      healthCheckPath: '/health'
      appSettings: [
        { name: 'ASPNETCORE_ENVIRONMENT'; value: environment == 'prod' ? 'Production' : 'Staging' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'; value: appInsightsConnectionString }
        { name: 'ConnectionStrings__DefaultConnection'; value: '@Microsoft.KeyVault(VaultName=${split(keyVaultUri, '.')[0]};SecretName=postgres-connection-string)' }
      ]
    }
    virtualNetworkSubnetId: appSubnetId
  }
}

output resourceId string = webApp.id
output principalId string = webApp.identity.principalId
output defaultHostName string = webApp.properties.defaultHostName
```

### PostgreSQL Module (`modules/postgresql.bicep`)

```bicep
param environment string
param location string
param appName string
param delegatedSubnetId string
param privateDnsZoneId string
param keyVaultName string
param adminUsername string = 'pgadmin'
param skuName string = environment == 'prod' ? 'Standard_D2s_v3' : 'Standard_B1ms'

var serverName = 'psql-${appName}-${environment}'

resource adminPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' existing = {
  name: '${keyVaultName}/postgres-admin-password'
}

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: skuName
    tier: environment == 'prod' ? 'GeneralPurpose' : 'Burstable'
  }
  properties: {
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword.properties.value
    version: '16'
    network: {
      delegatedSubnetResourceId: delegatedSubnetId
      privateDnsZoneArmResourceId: privateDnsZoneId
    }
    storage: {
      storageSizeGB: environment == 'prod' ? 32 : 16
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: environment == 'prod' ? 35 : 7
      geoRedundantBackup: environment == 'prod' ? 'Enabled' : 'Disabled'
    }
    highAvailability: {
      mode: environment == 'prod' ? 'ZoneRedundant' : 'Disabled'
    }
  }
}

output serverName string = postgresServer.name
output fqdn string = postgresServer.properties.fullyQualifiedDomainName
```

---

## Deployment Commands

### Prerequisites

```bash
# Install Bicep CLI (bundled with Azure CLI 2.20+)
az bicep install
az bicep version

# Upgrade to latest Bicep
az bicep upgrade
```

### Deploy to Resource Group

```bash
RESOURCE_GROUP="rg-auth-framework-prod"
LOCATION="eastus2"
ENVIRONMENT="prod"

# Create resource group if it doesn't exist
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# Deploy using the parameter file for the environment
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "deploy-$(date +%Y%m%d-%H%M%S)" \
  --template-file bicep/main.bicep \
  --parameters bicep/parameters/$ENVIRONMENT.bicepparam \
  --verbose
```

### Deploy Individual Modules

```bash
# Deploy only the networking module
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "networking-$(date +%Y%m%d)" \
  --template-file bicep/modules/networking.bicep \
  --parameters environment="$ENVIRONMENT" appName="auth-framework"
```

### Deploy at Subscription Level

For resource group creation as part of the deployment:

```bash
az deployment sub create \
  --location "$LOCATION" \
  --name "sub-deploy-$(date +%Y%m%d)" \
  --template-file bicep/subscription-level.bicep \
  --parameters environment="$ENVIRONMENT"
```

---

## Parameter File Usage

### Bicep Parameters Format (`.bicepparam`)

```bicep
// bicep/parameters/prod.bicepparam
using '../main.bicep'

param environment = 'prod'
param location = 'eastus2'
param appName = 'auth-framework'
param appServiceSkuName = 'P1v3'
param appServiceMinCount = 2
param appServiceMaxCount = 10
param postgresSkuName = 'Standard_D2s_v3'
param postgresStorageGB = 32
param postgresBackupRetentionDays = 35
param postgresHighAvailability = true
param postgresGeoRedundantBackup = true
param acrSku = 'Premium'
param logRetentionDays = 90
```

### JSON Parameters Format (`.parameters.json`)

For compatibility with older tooling:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environment": { "value": "prod" },
    "location": { "value": "eastus2" },
    "appName": { "value": "auth-framework" },
    "postgresHighAvailability": { "value": true }
  }
}
```

```bash
# Deploy with JSON parameter file
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file bicep/main.bicep \
  --parameters @bicep/parameters/prod.parameters.json
```

---

## What-If Deployments

The `--what-if` flag previews changes without applying them. This is equivalent to
`terraform plan` and should be run before every production deployment.

```bash
# Preview changes
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file bicep/main.bicep \
  --parameters bicep/parameters/prod.bicepparam

# What-if with confirmation prompt before applying
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file bicep/main.bicep \
  --parameters bicep/parameters/prod.bicepparam \
  --confirm-with-what-if
```

### Interpreting What-If Output

| Symbol | Meaning |
|---|---|
| `+` (green) | Resource will be created |
| `~` (yellow) | Resource will be modified |
| `-` (red) | Resource will be deleted |
| `×` (red) | Resource will be deleted and recreated |
| `≈` (purple) | Resource has no changes |
| `?` (gray) | Impact unknown |

Any `-` or `×` entries should be reviewed carefully before proceeding with a production
deployment.

---

## Bicep vs Terraform Comparison

| Aspect | Bicep | Terraform |
|---|---|---|
| **Language** | Domain-specific (ARM-native) | HCL (HashiCorp) |
| **Provider support** | Azure only | Multi-cloud (AWS, GCP, Azure, etc.) |
| **State management** | No state file; uses ARM directly | Requires state file (blob backend) |
| **Idempotency** | ARM handles idempotency natively | State-based idempotency |
| **Module ecosystem** | Azure Verified Modules (AVM) | Terraform Registry (large ecosystem) |
| **Drift detection** | `what-if` shows drift at deploy time | `terraform plan` detects drift |
| **Import existing resources** | `az bicep generate-params` + manual | `terraform import` |
| **Learning curve** | Low for Azure-only teams | Higher initial investment |
| **CI/CD integration** | Azure DevOps native; GitHub Actions | GitHub Actions; broad support |
| **Preview changes** | `--what-if` flag | `terraform plan` |
| **Secret handling** | Key Vault references in ARM | Terraform sensitive values + Key Vault |
| **Cost** | Free | Free (open source); paid for Terraform Cloud |

### When to Choose Bicep

- Your team works exclusively with Azure and has no plans to use other clouds.
- You want the closest fidelity to the Azure Resource Manager API.
- You prefer not to manage a Terraform state file.
- You are already using Azure DevOps pipelines with built-in Bicep task support.

### When to Choose Terraform

- You need to manage resources across multiple cloud providers.
- Your team already has Terraform expertise.
- You want a rich module ecosystem and community support.
- You need advanced features like complex loops, dynamic blocks, and provider aliasing.

This project provides both options. Terraform is the recommended choice for production
deployments due to its mature ecosystem and explicit state management, but Bicep templates
are provided for teams that prefer it.
