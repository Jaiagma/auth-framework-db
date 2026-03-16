# Azure CLI Commands Reference

Quick-reference guide for all Azure CLI commands used to manage the Auth Framework API
deployment. All commands assume the relevant environment variables are set.

---

## Environment Variables

Set these before running commands to avoid repeating arguments:

```bash
export RESOURCE_GROUP="rg-auth-framework-prod"
export LOCATION="eastus2"
export APP_SERVICE_NAME="app-auth-framework-prod"
export ACR_NAME="crauthframeworkprod"
export ACR_LOGIN_SERVER="$ACR_NAME.azurecr.io"
export KV_NAME="kv-auth-framework-prod"
export PG_SERVER_NAME="psql-auth-framework-prod"
export PG_ADMIN="pgadmin"
export PG_DB="authdb"
```

---

## Authentication Commands

```bash
# Interactive login (browser)
az login

# Device-code login (headless servers, WSL)
az login --use-device-code

# Service principal login (CI/CD)
az login \
  --service-principal \
  --username "$ARM_CLIENT_ID" \
  --password "$ARM_CLIENT_SECRET" \
  --tenant "$ARM_TENANT_ID"

# Managed Identity login (from within an Azure VM or App Service)
az login --identity

# Show current login context
az account show

# List all available subscriptions
az account list --output table

# Switch subscription
az account set --subscription "<subscription-id-or-name>"

# Log out
az logout
```

---

## Resource Group Commands

```bash
# Create a resource group
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --tags environment=prod project=auth-framework

# List all resource groups
az group list --output table

# Show resource group details
az group show --name "$RESOURCE_GROUP"

# List all resources within a group
az resource list \
  --resource-group "$RESOURCE_GROUP" \
  --output table

# Delete a resource group (and all resources inside it)
az group delete \
  --name "$RESOURCE_GROUP" \
  --yes \
  --no-wait

# Create a delete lock on a resource group
az lock create \
  --name "DoNotDelete" \
  --resource-group "$RESOURCE_GROUP" \
  --lock-type CanNotDelete

# List locks
az lock list --resource-group "$RESOURCE_GROUP" --output table
```

---

## App Service Commands

### Deployment

```bash
# Set container image for the production slot
az webapp config container set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --docker-custom-image-name "$ACR_LOGIN_SERVER/auth-framework-api:$IMAGE_TAG" \
  --docker-registry-server-url "https://$ACR_LOGIN_SERVER"

# Set container image for the staging slot
az webapp config container set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --slot staging \
  --docker-custom-image-name "$ACR_LOGIN_SERVER/auth-framework-api:$IMAGE_TAG"

# Force pull the latest image (useful after pushing a new :latest)
az webapp restart \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"
```

### Slot Management

```bash
# List all deployment slots
az webapp deployment slot list \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --output table

# Swap staging to production
az webapp deployment slot swap \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --slot staging \
  --target-slot production

# Preview swap (shows which settings would change)
az webapp deployment slot swap \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --slot staging \
  --target-slot production \
  --action preview

# Reset slot swap preview (cancel without swapping)
az webapp deployment slot swap \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --slot staging \
  --target-slot production \
  --action reset
```

### Configuration

```bash
# List all app settings
az webapp config appsettings list \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --output table

# Set a single app setting
az webapp config appsettings set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --settings ASPNETCORE_ENVIRONMENT=Production

# Set multiple app settings at once
az webapp config appsettings set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --settings \
    ASPNETCORE_ENVIRONMENT=Production \
    FeatureFlags__NewAuthFlow=true

# Delete an app setting
az webapp config appsettings delete \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --setting-names "OLD_SETTING"
```

### Restart and Scaling

```bash
# Restart the app
az webapp restart \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"

# Stop / start the app
az webapp stop --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP"
az webapp start --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP"

# Scale out App Service Plan manually
az appservice plan update \
  --name "asp-auth-framework-prod" \
  --resource-group "$RESOURCE_GROUP" \
  --number-of-workers 4
```

### Logs

```bash
# Stream live application logs
az webapp log tail \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"

# Stream logs from the staging slot
az webapp log tail \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --slot staging

# Download log archive
az webapp log download \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --log-file "app-logs-$(date +%Y%m%d).zip"

# Show recent container events
az webapp log show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --provider docker
```

---

## PostgreSQL Commands

### Connection

```bash
# Connect interactively
az postgres flexible-server connect \
  --name "$PG_SERVER_NAME" \
  --admin-user "$PG_ADMIN" \
  --admin-password "$PG_ADMIN_PASSWORD" \
  --database-name "$PG_DB"

# Execute a single query
az postgres flexible-server connect \
  --name "$PG_SERVER_NAME" \
  --admin-user "$PG_ADMIN" \
  --admin-password "$PG_ADMIN_PASSWORD" \
  --database-name "$PG_DB" \
  --querytext "SELECT COUNT(*) FROM users;"

# Execute a SQL file
az postgres flexible-server execute \
  --name "$PG_SERVER_NAME" \
  --admin-user "$PG_ADMIN" \
  --admin-password "$PG_ADMIN_PASSWORD" \
  --database-name "$PG_DB" \
  --file-path "migrations/0001_initial.sql"
```

### Firewall Rules

```bash
# Add a firewall rule for your current IP
MY_IP=$(curl -s https://api.ipify.org)
az postgres flexible-server firewall-rule create \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --rule-name "my-ip-$(date +%Y%m%d)" \
  --start-ip-address "$MY_IP" \
  --end-ip-address "$MY_IP"

# List firewall rules
az postgres flexible-server firewall-rule list \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --output table

# Delete a firewall rule
az postgres flexible-server firewall-rule delete \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --rule-name "my-ip-20240101" \
  --yes
```

### Server Configuration

```bash
# List all server parameters
az postgres flexible-server parameter list \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --output table

# Get a single parameter
az postgres flexible-server parameter show \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --parameter-name "max_connections"

# Update a server parameter
az postgres flexible-server parameter set \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --parameter-name "max_connections" \
  --value "200"

# Restart the server (required for some parameter changes)
az postgres flexible-server restart \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP"
```

---

## Key Vault Commands

### Access Policies and RBAC

```bash
# Assign Key Vault Secrets User role to a managed identity
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee "$APP_PRINCIPAL_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME"

# Assign Key Vault Secrets Officer to a CI/CD service principal
az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee "$SERVICE_PRINCIPAL_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME"

# List role assignments on the Key Vault
az role assignment list \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME" \
  --output table
```

### Secret Operations

```bash
# Set a secret
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "my-secret" \
  --value "my-secret-value"

# Get a secret value
az keyvault secret show \
  --vault-name "$KV_NAME" \
  --name "my-secret" \
  --query value \
  --output tsv

# List all secrets (names only)
az keyvault secret list \
  --vault-name "$KV_NAME" \
  --output table

# Delete a secret (soft delete)
az keyvault secret delete \
  --vault-name "$KV_NAME" \
  --name "my-secret"

# Recover a soft-deleted secret
az keyvault secret recover \
  --vault-name "$KV_NAME" \
  --name "my-secret"

# Purge (permanently delete) a soft-deleted secret
az keyvault secret purge \
  --vault-name "$KV_NAME" \
  --name "my-secret"
```

---

## ACR Commands

```bash
# Authenticate to ACR
az acr login --name "$ACR_NAME"

# List repositories
az acr repository list --name "$ACR_NAME" --output table

# List tags for a repository
az acr repository show-tags \
  --name "$ACR_NAME" \
  --repository "auth-framework-api" \
  --orderby time_desc \
  --output table

# Build and push an image using ACR Tasks
az acr build \
  --registry "$ACR_NAME" \
  --image "auth-framework-api:$IMAGE_TAG" \
  --file Dockerfile \
  .

# Delete an old image tag
az acr repository delete \
  --name "$ACR_NAME" \
  --image "auth-framework-api:old-tag" \
  --yes

# Purge images older than 30 days (keeping last 10 tags)
az acr run \
  --cmd "acr purge --filter 'auth-framework-api:.*' --ago 30d --keep 10" \
  --registry "$ACR_NAME" \
  /dev/null
```

---

## Monitoring Commands

```bash
# Stream App Service metrics
az monitor metrics list \
  --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$APP_SERVICE_NAME" \
  --metric "CpuPercentage" \
  --interval PT1M \
  --output table

# Show recent activity log for resource group
az monitor activity-log list \
  --resource-group "$RESOURCE_GROUP" \
  --start-time "$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --output table

# Query Log Analytics workspace
az monitor log-analytics query \
  --workspace "$LOG_ANALYTICS_WORKSPACE_ID" \
  --analytics-query "AppRequests | where TimeGenerated > ago(1h) | summarize count() by ResultCode" \
  --output table

# List alert rules
az monitor alert list \
  --resource-group "$RESOURCE_GROUP" \
  --output table
```
