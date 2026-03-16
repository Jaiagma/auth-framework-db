# Azure Portal Manual Setup Guide

## Step 1: Resource Group
1. Go to **Resource Groups** → **+ Create**
2. Name: `rg-authframework-dev`, Region: `East US 2`

## Step 2: Key Vault
1. Search **Key Vault** → **+ Create**
2. Name: `authframework-dev-kv`, same RG/region, SKU: Standard
3. After creation, go to **Secrets** → add: `db-password`, `jwt-secret-key`, `encryption-key`

## Step 3: Container Registry
1. Search **Container registries** → **+ Create**
2. Name: `authframeworkdevacr`, SKU: Basic, Admin user: Enabled

## Step 4: PostgreSQL Flexible Server
1. Search **Azure Database for PostgreSQL** → **Flexible Server** → **+ Create**
2. Server name: `authframework-dev-psql`, Version: 16, SKU: Burstable B1ms
3. Admin: `psqladmin`, set password, record it

## Step 5: App Service
1. Search **App Services** → **+ Create** → **Web App**
2. Name: `authframework-dev-api`, Publish: Docker Container, OS: Linux
3. Plan: B2
4. Under **Docker** tab: Image Source = Azure Container Registry, select your ACR/image
5. After creation: **Identity** → System assigned → **On**
6. Copy the **Object ID**, go to Key Vault → **Access policies** → Add the identity with Get+List secrets

## Step 6: Application Settings
In the App Service **Configuration** → **Application settings**, add:
- `ConnectionStrings__DefaultConnection` = `@Microsoft.KeyVault(VaultName=authframework-dev-kv;SecretName=db-connection-string)`
- `JwtSettings__SecretKey` = `@Microsoft.KeyVault(VaultName=authframework-dev-kv;SecretName=jwt-secret-key)`
- `ASPNETCORE_URLS` = `http://+:8080`

## Verification
Browse to `https://authframework-dev-api.azurewebsites.net/health` — expect HTTP 200.
