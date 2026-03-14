# Azure Security Best Practices

This guide documents the security architecture and best practices applied to the Auth
Framework API deployment on Azure.

---

## Table of Contents

1. [Managed Identities](#managed-identities)
2. [Key Vault for Secrets](#key-vault-for-secrets)
3. [Network Security](#network-security)
4. [TLS/SSL Configuration](#tlsssl-configuration)
5. [RBAC Principles](#rbac-principles)
6. [PostgreSQL Security](#postgresql-security)
7. [Container Security](#container-security)
8. [Secret Rotation](#secret-rotation)
9. [Compliance Checklist](#compliance-checklist)

---

## Managed Identities

Managed Identities eliminate the need to store credentials in application configuration,
environment variables, or code. The App Service's system-assigned identity is used to
authenticate to Key Vault, ACR, and Azure Storage without any secrets.

### Enable Managed Identity

```bash
# Enable system-assigned identity on the App Service
az webapp identity assign \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"

# Capture the principal ID for role assignments
APP_PRINCIPAL_ID=$(az webapp identity show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query principalId \
  --output tsv)

echo "Principal ID: $APP_PRINCIPAL_ID"
```

### Grant Minimum Required Permissions

```bash
# Key Vault Secrets User — read-only secret access (not officer)
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee "$APP_PRINCIPAL_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME"

# AcrPull — pull images from ACR (not push)
az role assignment create \
  --role "AcrPull" \
  --assignee "$APP_PRINCIPAL_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_NAME"

# Storage Blob Data Reader — read application assets if needed
az role assignment create \
  --role "Storage Blob Data Reader" \
  --assignee "$APP_PRINCIPAL_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"
```

---

## Key Vault for Secrets

All secrets are stored in Azure Key Vault. The application accesses them through Key
Vault references in App Service configuration — the App Service platform resolves these
at startup, so secrets are never exposed in the Azure portal or in plain environment
variables.

### Key Vault Reference Syntax

```
@Microsoft.KeyVault(VaultName=kv-auth-framework-prod;SecretName=postgres-connection-string)
```

Or using the full secret URI (preferred, as it pins a specific version):

```
@Microsoft.KeyVault(SecretUri=https://kv-auth-framework-prod.vault.azure.net/secrets/postgres-connection-string/abc123)
```

### Set Secrets

```bash
# Store the database connection string
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "postgres-connection-string" \
  --value "Host=$PG_FQDN;Port=5432;Database=authdb;Username=$PG_USER;Password=$PG_PASSWORD;Ssl Mode=Require"

# Store the JWT signing key (generate a strong key)
JWT_KEY=$(openssl rand -base64 64)
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "app-jwt-signing-key" \
  --value "$JWT_KEY"
```

### Key Vault Access Control

```bash
# Disable public network access (private endpoint only)
az keyvault update \
  --name "$KV_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --public-network-access Disabled

# Enable purge protection to prevent hard-delete of secrets
az keyvault update \
  --name "$KV_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --enable-purge-protection true

# Set soft-delete retention to maximum (90 days for production)
az keyvault update \
  --name "$KV_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --retention-days 90
```

---

## Network Security

### VNet Architecture

All resources are deployed within a Virtual Network. Database and Key Vault have no
public endpoints. Traffic between the application and backend services stays on the Azure
backbone.

```
Public Internet
    │
    ▼  HTTPS only (TLS 1.2+)
Azure Front Door (WAF enabled)
    │
    ▼
App Service (VNet Integration → app-subnet 10.0.1.0/24)
    │
    ├── PostgreSQL (data-subnet 10.0.2.0/24, no public endpoint)
    ├── Key Vault (private endpoint in pe-subnet 10.0.3.0/24)
    └── ACR (private endpoint in pe-subnet 10.0.3.0/24)
```

### NSG Rules Configuration

```bash
# Create NSG for the app subnet
az network nsg create \
  --name "nsg-app-subnet" \
  --resource-group "$RESOURCE_GROUP"

# Allow inbound only from Azure Front Door
az network nsg rule create \
  --nsg-name "nsg-app-subnet" \
  --resource-group "$RESOURCE_GROUP" \
  --name "AllowAzureFrontDoor" \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix AzureFrontDoor.Backend \
  --destination-port-ranges 443

# Allow Azure Load Balancer health probes
az network nsg rule create \
  --nsg-name "nsg-app-subnet" \
  --resource-group "$RESOURCE_GROUP" \
  --name "AllowAzureLoadBalancer" \
  --priority 200 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefix AzureLoadBalancer \
  --destination-port-ranges 443

# Deny all other inbound traffic
az network nsg rule create \
  --nsg-name "nsg-app-subnet" \
  --resource-group "$RESOURCE_GROUP" \
  --name "DenyAllInbound" \
  --priority 4096 \
  --direction Inbound \
  --access Deny \
  --protocol "*" \
  --source-address-prefix "*" \
  --destination-port-ranges "*"
```

### Private Endpoints

```bash
# Create private endpoint for Key Vault
az network private-endpoint create \
  --name "pe-keyvault" \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "vnet-auth-framework-prod" \
  --subnet "pe-subnet" \
  --private-connection-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME" \
  --group-id vault \
  --connection-name "kv-connection"
```

---

## TLS/SSL Configuration

```bash
# Enforce HTTPS-only on App Service
az webapp update \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --https-only true

# Set minimum TLS version to 1.2
az webapp config set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --min-tls-version 1.2

# Disable FTP (use deployment slots or zip deploy instead)
az webapp config set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --ftps-state Disabled
```

### Custom Domain with Managed Certificate

```bash
# Bind a custom domain
az webapp config hostname add \
  --webapp-name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --hostname "api.example.com"

# Create and bind a free App Service Managed Certificate
az webapp config ssl create \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --hostname "api.example.com"
```

---

## RBAC Principles

Apply the principle of least privilege for all identities:

| Identity | Role | Scope |
|---|---|---|
| App Service (Managed Identity) | Key Vault Secrets User | Key Vault resource |
| App Service (Managed Identity) | AcrPull | ACR resource |
| CI/CD Service Principal | Contributor | Resource group |
| CI/CD Service Principal | Key Vault Secrets Officer | Key Vault resource |
| CI/CD Service Principal | AcrPush | ACR resource |
| Developer (AAD user) | Reader | Resource group |
| On-call Engineer | Key Vault Reader | Key Vault resource |
| DBA | Contributor | PostgreSQL resource only |

```bash
# Example: grant a developer read-only access
az role assignment create \
  --role "Reader" \
  --assignee "developer@example.com" \
  --resource-group "$RESOURCE_GROUP"

# Never grant Owner or Contributor at subscription level for application identities
```

---

## PostgreSQL Security

```bash
# Ensure SSL is required (verify it is not disabled)
az postgres flexible-server parameter show \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --parameter-name "require_secure_transport"

# Enable pg_audit extension for audit logging
az postgres flexible-server parameter set \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --parameter-name "azure.extensions" \
  --value "pg_audit"

az postgres flexible-server parameter set \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --parameter-name "pgaudit.log" \
  --value "DDL,WRITE"
```

### Row-Level Security

RLS policies are defined in `rls_policies.sql` and enforce tenant isolation at the
database layer. Key patterns used:

```sql
-- Enable RLS on the table
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Policy: users can only see their own tenant's data
CREATE POLICY tenant_isolation ON users
  USING (tenant_id = current_setting('app.current_tenant_id')::uuid);

-- Application code sets the tenant context on each connection
SET LOCAL app.current_tenant_id = '<tenant-uuid>';
```

---

## Container Security

### Dockerfile Best Practices

```dockerfile
# Use a specific, non-latest base image tag
FROM mcr.microsoft.com/dotnet/aspnet:9.0-noble-chiseled AS runtime

# Run as non-root user (chiseled images use app user by default)
USER app

# Set read-only filesystem (secrets must be mounted as volumes or env vars)
# Pass --read-only flag when running containers

# Do not copy sensitive files into the image
COPY --chown=app:app ./publish /app

WORKDIR /app
ENTRYPOINT ["dotnet", "AuthFramework.Api.dll"]
```

### Verify No Secrets in Image

```bash
# Scan for secrets accidentally baked into the image
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image \
  --exit-code 1 \
  --severity HIGH,CRITICAL \
  "$ACR_LOGIN_SERVER/auth-framework-api:$IMAGE_TAG"
```

---

## Secret Rotation

### Rotate PostgreSQL Password

```bash
# 1. Generate a new strong password
NEW_PG_PASSWORD=$(openssl rand -base64 32)

# 2. Update the password in PostgreSQL
az postgres flexible-server update \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --admin-password "$NEW_PG_PASSWORD"

# 3. Update the secret in Key Vault (creates a new version)
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "postgres-admin-password" \
  --value "$NEW_PG_PASSWORD"

# 4. Update the connection string secret
NEW_CONN_STRING="Host=$PG_FQDN;Port=5432;Database=authdb;Username=$PG_ADMIN;Password=$NEW_PG_PASSWORD;Ssl Mode=Require"
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "postgres-connection-string" \
  --value "$NEW_CONN_STRING"

# 5. Restart the App Service to pick up the new Key Vault reference
az webapp restart --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP"
```

### Rotate JWT Signing Key

```bash
NEW_JWT_KEY=$(openssl rand -base64 64)
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "app-jwt-signing-key" \
  --value "$NEW_JWT_KEY"

# Restart to pick up the new key (note: existing valid JWTs will be invalidated)
az webapp restart --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP"
```

---

## Compliance Checklist

### Network

- [ ] All services deployed within a VNet
- [ ] No public endpoints on database or Key Vault
- [ ] Private endpoints configured for Key Vault and ACR
- [ ] NSGs applied to all subnets with least-privilege rules
- [ ] Azure Front Door WAF enabled with OWASP rule set
- [ ] DDoS Protection Standard enabled on VNet

### Identity and Access

- [ ] Managed Identity used; no credentials in app config
- [ ] All RBAC assignments at resource or resource-group scope (not subscription)
- [ ] No standing admin access to production database (JIT enabled)
- [ ] Service principal credentials rotated on a schedule
- [ ] MFA required for all human identities with Azure portal access

### Data

- [ ] Data encrypted at rest (AES-256) — Azure default
- [ ] Data encrypted in transit (TLS 1.2+) — enforced on App Service and PostgreSQL
- [ ] Customer-managed encryption keys configured (if required by compliance)
- [ ] Backup encryption enabled
- [ ] Geo-redundant backups enabled for production

### Application

- [ ] HTTPS-only enforced on App Service
- [ ] Minimum TLS version set to 1.2
- [ ] FTP disabled
- [ ] Container running as non-root user
- [ ] No secrets in Docker image layers
- [ ] Dependency vulnerability scanning in CI/CD pipeline

### Monitoring and Audit

- [ ] Diagnostic settings configured for all resources
- [ ] Key Vault audit logging enabled
- [ ] PostgreSQL audit logging (pg_audit) enabled
- [ ] Activity log retention set to 90+ days
- [ ] Security alerts configured in Microsoft Defender for Cloud
- [ ] Alerts on anomalous login patterns configured
