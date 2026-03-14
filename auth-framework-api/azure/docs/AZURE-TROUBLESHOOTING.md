# Azure Troubleshooting Guide

Diagnosis and resolution steps for common issues with the Auth Framework API on Azure.

---

## Table of Contents

1. [App Service Issues](#app-service-issues)
2. [PostgreSQL Connectivity Issues](#postgresql-connectivity-issues)
3. [Key Vault Access Issues](#key-vault-access-issues)
4. [Docker and ACR Issues](#docker-and-acr-issues)
5. [Deployment Failures](#deployment-failures)
6. [Log Collection Commands](#log-collection-commands)
7. [Diagnostic Commands Reference](#diagnostic-commands-reference)

---

## App Service Issues

### Container Fails to Start

**Symptom:** App Service shows status `Application Error` or the container restart-loops.

**Diagnosis:**

```bash
# Stream live container logs
az webapp log tail \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"

# Check recent container events
az webapp log show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --provider docker

# Show container settings
az webapp config container show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"

# Check app settings (look for missing or malformed Key Vault references)
az webapp config appsettings list \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --output table
```

**Common causes and fixes:**

| Cause | Symptom in Logs | Fix |
|---|---|---|
| Missing environment variable | `KeyNotFoundException` or `NullReferenceException` at startup | Add the missing app setting |
| Invalid Key Vault reference | `Microsoft.KeyVault.SecretNotFound` | Verify secret name and vault name spelling |
| Key Vault access denied | `403 Forbidden` from Key Vault | Grant `Key Vault Secrets User` to the managed identity |
| Wrong image tag | `manifest unknown` | Verify image tag exists in ACR |
| Port mismatch | Container starts but health check fails | Ensure `WEBSITES_PORT` is set to `8080` (or match your app's port) |
| Database unreachable | `Npgsql.NpgsqlException: Connection refused` | Check VNet integration and NSG rules |

```bash
# Check WEBSITES_PORT setting
az webapp config appsettings list \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?name=='WEBSITES_PORT']"

# Set correct port if missing
az webapp config appsettings set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --settings WEBSITES_PORT=8080
```

### Health Check Failures

**Symptom:** App is running but marked as unhealthy; instances are being replaced.

```bash
# Check health check configuration
az webapp show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "siteConfig.healthCheckPath"

# Test the health endpoint manually
APP_HOSTNAME=$(az webapp show -n "$APP_SERVICE_NAME" -g "$RESOURCE_GROUP" --query defaultHostName -o tsv)
curl -v "https://$APP_HOSTNAME/health"

# Check health check threshold (how many failures before instance is replaced)
az webapp config show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "healthCheckEvictionTime"
```

**Fix:** Ensure the `/health` endpoint returns `200 OK` within 240 seconds of startup.
Increase the health check grace period if the app needs more time to initialize:

```bash
az webapp config set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --generic-configurations '{"healthCheckEvictionTime": 10}'
```

### 502 Bad Gateway / 503 Service Unavailable

**Symptom:** HTTP 502 or 503 responses from the application.

```bash
# 502: usually means the container crashed after a request started
# Check for application exceptions
az webapp log tail \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"

# 503: usually means no healthy instances are available
# Check instance health
az webapp show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "instanceCount"

# Check if auto-scale is hitting the maximum
az monitor autoscale show \
  --name "autoscale-auth-framework-prod" \
  --resource-group "$RESOURCE_GROUP"
```

**Quick resolution:**

```bash
# Restart the app service to cycle all instances
az webapp restart \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"
```

---

## PostgreSQL Connectivity Issues

### SSL Certificate Error

**Symptom:** `Npgsql.NpgsqlException: The remote certificate is invalid`

**Fix:** Ensure the connection string includes `Ssl Mode=Require` but does not set
`Trust Server Certificate=true` (which would bypass validation). Download the DigiCert
Global Root CA certificate:

```bash
curl -o /etc/ssl/certs/digicert-global-root-g2.crt \
  https://dl.cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem
```

Or pass the root certificate path in the connection string:

```
Ssl Mode=VerifyFull;Root Certificate=/etc/ssl/certs/digicert-global-root-g2.crt
```

### Connection Timeout

**Symptom:** `Npgsql.NpgsqlException: Timeout during connection attempt`

**Diagnosis:**

```bash
# Verify VNet integration is configured
az webapp vnet-integration list \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"

# Check NSG rules on the data subnet allow port 5432 from app subnet
az network nsg rule list \
  --nsg-name "nsg-data-subnet" \
  --resource-group "$RESOURCE_GROUP" \
  --output table

# Verify PostgreSQL server is running
az postgres flexible-server show \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "state"
```

**Fix:** If VNet integration is missing, re-add it:

```bash
az webapp vnet-integration add \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --vnet "vnet-auth-framework-prod" \
  --subnet "app-subnet"
```

### Connection Refused

**Symptom:** `Npgsql.NpgsqlException: Connection refused (port 5432)`

```bash
# Check if the server is stopped
az postgres flexible-server start \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP"

# Connect directly to verify server is reachable
az postgres flexible-server connect \
  --name "$PG_SERVER_NAME" \
  --admin-user "$PG_ADMIN" \
  --admin-password "$PG_ADMIN_PASSWORD" \
  --database-name "$PG_DB" \
  --querytext "SELECT 1;"
```

### Too Many Connections

**Symptom:** `FATAL: remaining connection slots are reserved for non-replication superuser connections`

```bash
# Check current connection count
az postgres flexible-server connect \
  --name "$PG_SERVER_NAME" \
  --admin-user "$PG_ADMIN" \
  --admin-password "$PG_ADMIN_PASSWORD" \
  --database-name "postgres" \
  --querytext "SELECT count(*) FROM pg_stat_activity;"

# See connections per application
az postgres flexible-server connect \
  --name "$PG_SERVER_NAME" \
  --admin-user "$PG_ADMIN" \
  --admin-password "$PG_ADMIN_PASSWORD" \
  --database-name "postgres" \
  --querytext "SELECT application_name, count(*) FROM pg_stat_activity GROUP BY application_name ORDER BY count DESC;"
```

**Fix:** Reduce `Maximum Pool Size` in the NpgSql connection string, or deploy PgBouncer.
See [AZURE-PERFORMANCE.md](./AZURE-PERFORMANCE.md) for PgBouncer configuration.

---

## Key Vault Access Issues

### 403 Forbidden

**Symptom:** `Microsoft.Azure.KeyVault.Models.KeyVaultErrorException: 403 Forbidden`

**Diagnosis:**

```bash
# Check role assignments on the Key Vault
az role assignment list \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME" \
  --output table

# Get the App Service's managed identity principal ID
APP_PRINCIPAL_ID=$(az webapp identity show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query principalId \
  --output tsv)

echo "App Principal ID: $APP_PRINCIPAL_ID"

# Check if the assignment exists
az role assignment list \
  --assignee "$APP_PRINCIPAL_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME"
```

**Fix:** Grant the required role:

```bash
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee "$APP_PRINCIPAL_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME"
```

### Key Vault Reference Not Resolving

**Symptom:** App setting shows literal `@Microsoft.KeyVault(...)` string instead of secret value.

```bash
# Check the Key Vault reference status
az webapp config appsettings list \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?name=='ConnectionStrings__DefaultConnection']"

# Check App Service Key Vault reference status
az webapp show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "siteConfig.keyVaultReferenceIdentity"
```

**Common causes:**
- Secret name has a typo in the reference
- Key Vault name has a typo
- Managed identity does not have access
- Key Vault public network access is blocked and private endpoint is not configured

---

## Docker and ACR Issues

### Authentication Failed (401)

```bash
# Re-authenticate to ACR
az acr login --name "$ACR_NAME"

# For CI/CD, ensure the service principal has AcrPush role
az role assignment create \
  --role "AcrPush" \
  --assignee "$CI_SERVICE_PRINCIPAL_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_NAME"
```

### Image Not Found (manifest unknown)

```bash
# List available tags
az acr repository show-tags \
  --name "$ACR_NAME" \
  --repository "auth-framework-api" \
  --output table

# Verify the exact tag used in App Service config
az webapp config container show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"
```

---

## Deployment Failures

### Terraform Apply Fails

```bash
# Common: state lock not released after failed apply
terraform force-unlock <LOCK_ID>

# Show detailed error
terraform apply -var-file="terraform.tfvars" -out="plan.tfplan" 2>&1 | tee apply.log

# Retry with a specific target if one resource is failing
terraform apply -target="module.app_service.azurerm_linux_web_app.main"
```

### EF Core Migration Fails

```bash
# Check pending migrations
dotnet ef migrations list \
  --project AuthFramework.Infrastructure \
  --startup-project AuthFramework.Api

# Apply with verbose output
dotnet ef database update \
  --project AuthFramework.Infrastructure \
  --startup-project AuthFramework.Api \
  --verbose 2>&1 | tee migration.log

# If a migration is partially applied, check the migration history table
# Then manually fix and mark as applied
dotnet ef database update <PreviousMigrationName>
```

---

## Log Collection Commands

```bash
# Download complete application logs as a zip archive
az webapp log download \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --log-file "logs-$(date +%Y%m%d-%H%M).zip"

# Stream logs in real time (Ctrl+C to stop)
az webapp log tail \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"

# Query Application Insights for exceptions in the last hour
az monitor log-analytics query \
  --workspace "$LOG_ANALYTICS_WORKSPACE_ID" \
  --analytics-query "AppExceptions | where TimeGenerated > ago(1h) | order by TimeGenerated desc | take 50" \
  --output table

# Get activity log for the resource group (last 6 hours)
az monitor activity-log list \
  --resource-group "$RESOURCE_GROUP" \
  --start-time "$(date -u -d '6 hours ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --output table
```

---

## Diagnostic Commands Reference

| Scenario | Command |
|---|---|
| Stream app logs | `az webapp log tail -n $APP_SERVICE_NAME -g $RESOURCE_GROUP` |
| Check app settings | `az webapp config appsettings list -n $APP_SERVICE_NAME -g $RESOURCE_GROUP` |
| Restart app | `az webapp restart -n $APP_SERVICE_NAME -g $RESOURCE_GROUP` |
| Check VNet integration | `az webapp vnet-integration list -n $APP_SERVICE_NAME -g $RESOURCE_GROUP` |
| Connect to database | `az postgres flexible-server connect -n $PG_SERVER_NAME --admin-user $PG_ADMIN ...` |
| Check NSG rules | `az network nsg rule list --nsg-name nsg-data-subnet -g $RESOURCE_GROUP` |
| Check Key Vault access | `az role assignment list --assignee $APP_PRINCIPAL_ID` |
| List ACR images | `az acr repository show-tags --name $ACR_NAME --repository auth-framework-api` |
| View container events | `az webapp log show -n $APP_SERVICE_NAME -g $RESOURCE_GROUP --provider docker` |
| Check autoscale | `az monitor autoscale show --name autoscale-... -g $RESOURCE_GROUP` |
