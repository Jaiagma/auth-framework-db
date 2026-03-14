# Managed Identities Setup Guide

---

## What Are Managed Identities?

A Managed Identity is an Azure Active Directory identity automatically managed by Azure.
It allows Azure services (like App Service) to authenticate to other Azure services
(Key Vault, ACR, Storage) **without storing any credentials** in code, config files, or
environment variables. Azure handles token acquisition and rotation automatically.

**Why use them:**
- No secrets to rotate, store, or accidentally leak
- Tokens are short-lived and automatically refreshed
- Audit trail in Azure AD sign-in logs
- Free to use

---

## System-Assigned vs User-Assigned

| Feature | System-Assigned | User-Assigned |
|---|---|---|
| Lifecycle | Tied to the resource (deleted with it) | Independent lifecycle |
| Sharing | One per resource | Can be shared across resources |
| Use case | Single resource needing identity | Multiple resources sharing permissions |
| Setup complexity | Simpler | Slightly more complex |

**This project uses system-assigned** identities for the App Service. Use user-assigned
identities when you need to pre-assign permissions before the resource exists (e.g., in
zero-downtime slot swap scenarios).

---

## Enabling Managed Identity on App Service

```bash
# Enable system-assigned identity
az webapp identity assign \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"

# Capture the principal ID
APP_PRINCIPAL_ID=$(az webapp identity show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query principalId --output tsv)

echo "Principal ID: $APP_PRINCIPAL_ID"

# Enable on staging slot too
az webapp identity assign \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --slot staging

STAGING_PRINCIPAL_ID=$(az webapp identity show \
  --name "$APP_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" \
  --slot staging --query principalId --output tsv)
```

---

## Granting Key Vault Access

```bash
# Grant Key Vault Secrets User (read secrets, not write)
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee "$APP_PRINCIPAL_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME"

# Grant staging slot identity
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee "$STAGING_PRINCIPAL_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME"
```

---

## Granting ACR Access (AcrPull)

```bash
ACR_RESOURCE_ID=$(az acr show --name "$ACR_NAME" --query id --output tsv)

az role assignment create \
  --role "AcrPull" \
  --assignee "$APP_PRINCIPAL_ID" \
  --scope "$ACR_RESOURCE_ID"

# Configure App Service to use managed identity for ACR pulls
az webapp config set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --generic-configurations '{"acrUseManagedIdentityCreds": true}'
```

---

## Granting Storage Access

```bash
STORAGE_RESOURCE_ID=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" --query id --output tsv)

az role assignment create \
  --role "Storage Blob Data Reader" \
  --assignee "$APP_PRINCIPAL_ID" \
  --scope "$STORAGE_RESOURCE_ID"
```

---

## Using Managed Identity in .NET Code

```csharp
// The DefaultAzureCredential automatically uses the managed identity when running in Azure
// and falls back to developer credentials locally (az login / VS login)

using Azure.Identity;
using Azure.Security.KeyVault.Secrets;

var credential = new DefaultAzureCredential();
var client = new SecretClient(new Uri(keyVaultUri), credential);
var secret = await client.GetSecretAsync("my-secret");
```

For EF Core with Azure AD authentication to PostgreSQL:

```csharp
builder.Services.AddDbContext<AppDbContext>(options =>
{
    options.UseNpgsql(connectionString, npgsql =>
        npgsql.ProvidePasswordCallback(async (host, port, database, username) =>
        {
            var credential = new DefaultAzureCredential();
            var token = await credential.GetTokenAsync(
                new TokenRequestContext(["https://ossrdbms-aad.database.windows.net/.default"]));
            return token.Token;
        }));
});
```

---

## Verification Commands

```bash
# Verify identity is assigned
az webapp identity show -n "$APP_SERVICE_NAME" -g "$RESOURCE_GROUP"

# List all role assignments for the identity
az role assignment list --assignee "$APP_PRINCIPAL_ID" --output table

# Test Key Vault access from App Service console (Kudu)
# Navigate to https://<app>.scm.azurewebsites.net/DebugConsole
# curl -H "Metadata: true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2019-08-01&resource=https://vault.azure.net"
```

---

## Troubleshooting Identity Issues

| Symptom | Cause | Fix |
|---|---|---|
| `403 Forbidden` from Key Vault | Role not assigned | Run `az role assignment create` above |
| `ManagedIdentityCredential: no identity` | Identity not enabled | Run `az webapp identity assign` |
| `401` pulling from ACR | `acrUseManagedIdentityCreds` not set | Set the config flag above |
| Role assignment exists but still 403 | Role propagation delay | Wait 5 minutes; Azure AD replication takes time |
| Works locally but not in Azure | Code using wrong credential | Use `DefaultAzureCredential`; don't hardcode `ClientSecretCredential` |
