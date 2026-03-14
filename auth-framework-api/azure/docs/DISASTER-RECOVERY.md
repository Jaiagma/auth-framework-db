# Disaster Recovery Procedures

---

## RTO/RPO Targets

| Environment | RTO | RPO | Strategy |
|---|---|---|---|
| Production | 1 hour | 15 minutes | Geo-redundant backup + Traffic Manager failover |
| Staging | 4 hours | 1 hour | Standard backup + redeploy |
| Development | 8 hours | 24 hours | Backup restore |

---

## Backup Strategy

### PostgreSQL Automated Backups

```bash
# Verify backup configuration
az postgres flexible-server show \
  --name "$PG_SERVER_NAME" --resource-group "$RESOURCE_GROUP" \
  --query "{backupRetentionDays:backup.backupRetentionDays, geoRedundant:backup.geoRedundantBackup}"

# List available restore points
az postgres flexible-server backup list \
  --name "$PG_SERVER_NAME" --resource-group "$RESOURCE_GROUP" --output table
```

Production settings:
- **Automated backups**: daily, 35-day retention
- **Geo-redundant**: enabled (backups replicated to paired region)
- **Point-in-time restore**: available to any second within the retention window

---

## Failover Procedures

### Region Failover (Step-by-Step)

**Prerequisites:** Secondary region infrastructure deployed via Terraform workspace.

```bash
# Step 1 — Confirm the primary region is unhealthy
az webapp show -n "$APP_SERVICE_NAME" -g "$RESOURCE_GROUP" --query state

# Step 2 — Restore database to secondary region
SECONDARY_RG="rg-auth-framework-prod-westus2"
RESTORE_TIME=$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')

az postgres flexible-server geo-restore \
  --name "psql-auth-framework-dr" \
  --resource-group "$SECONDARY_RG" \
  --source-server "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DBforPostgreSQL/flexibleServers/$PG_SERVER_NAME" \
  --location "westus2"

# Step 3 — Update connection string in secondary Key Vault
NEW_PG_FQDN="psql-auth-framework-dr.postgres.database.azure.com"
az keyvault secret set \
  --vault-name "kv-auth-framework-dr" \
  --name "postgres-connection-string" \
  --value "Host=$NEW_PG_FQDN;Port=5432;Database=authdb;Username=$PG_ADMIN;Password=$PG_PASSWORD;Ssl Mode=Require"

# Step 4 — Deploy latest image to secondary App Service
az webapp config container set \
  --name "app-auth-framework-dr" \
  --resource-group "$SECONDARY_RG" \
  --docker-custom-image-name "$ACR_LOGIN_SERVER/auth-framework-api:$IMAGE_TAG"

az webapp restart -n "app-auth-framework-dr" -g "$SECONDARY_RG"

# Step 5 — Verify secondary is healthy
curl -sf "https://app-auth-framework-dr.azurewebsites.net/health"

# Step 6 — Switch Traffic Manager endpoint
az network traffic-manager endpoint update \
  --name "primary-endpoint" \
  --profile-name "tm-auth-framework" \
  --resource-group "$RESOURCE_GROUP" \
  --type azureEndpoints \
  --endpoint-status Disabled

az network traffic-manager endpoint update \
  --name "secondary-endpoint" \
  --profile-name "tm-auth-framework" \
  --resource-group "$RESOURCE_GROUP" \
  --type azureEndpoints \
  --endpoint-status Enabled
```

---

## Database Restore Procedures

### Point-in-Time Restore

```bash
# Restore to a specific point in time (e.g., before a bad migration)
RESTORE_TIME="2024-01-15T14:30:00Z"

az postgres flexible-server restore \
  --name "psql-auth-framework-restored" \
  --resource-group "$RESOURCE_GROUP" \
  --source-server "$PG_SERVER_NAME" \
  --restore-time "$RESTORE_TIME"
```

### Promote Restored Server

```bash
# After validating data, update app to use restored server
NEW_FQDN=$(az postgres flexible-server show \
  -n "psql-auth-framework-restored" -g "$RESOURCE_GROUP" \
  --query fullyQualifiedDomainName -o tsv)

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "postgres-connection-string" \
  --value "Host=$NEW_FQDN;Port=5432;Database=authdb;Username=$PG_ADMIN;Password=$PG_PASSWORD;Ssl Mode=Require"

az webapp restart -n "$APP_SERVICE_NAME" -g "$RESOURCE_GROUP"
```

---

## DNS Failover with Traffic Manager

```bash
# Check Traffic Manager profile status
az network traffic-manager profile show \
  --name "tm-auth-framework" --resource-group "$RESOURCE_GROUP"

# List endpoints and their health
az network traffic-manager endpoint list \
  --profile-name "tm-auth-framework" \
  --resource-group "$RESOURCE_GROUP" --output table

# Manual failover: disable primary, enable secondary
az network traffic-manager endpoint update \
  --name "primary" --profile-name "tm-auth-framework" \
  --resource-group "$RESOURCE_GROUP" \
  --type azureEndpoints --endpoint-status Disabled
```

---

## DR Drill Procedures

Perform a DR drill quarterly in a non-production environment.

1. **Announce** the drill window to stakeholders (30 min planned downtime in staging)
2. **Snapshot** the current state: app version, DB row counts
3. **Execute** the failover procedure above against staging
4. **Validate** health endpoint, login flow, and DB record counts match
5. **Document** actual RTO achieved vs target
6. **Fail back** to primary region
7. **Retrospective**: document gaps and update this runbook

---

## Recovery Testing Checklist

- [ ] Database backup exists and is within RPO window
- [ ] Geo-redundant backup confirmed in secondary region
- [ ] Secondary region infrastructure provisioned and tested
- [ ] Traffic Manager failover tested
- [ ] Application starts successfully in secondary region
- [ ] Database restore completed within RTO
- [ ] Health check passes post-restore
- [ ] Smoke test: login, token refresh, and logout succeed
- [ ] Monitoring and alerts active in secondary region
- [ ] Runbook reviewed and updated after drill
