# Azure Deployment Guide

This guide walks through deploying the Auth Framework API to Microsoft Azure from scratch,
covering infrastructure provisioning, container image publishing, database migrations, and
post-deployment verification.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Azure Setup](#initial-azure-setup)
3. [Terraform Deployment](#terraform-deployment)
4. [Docker Build and Push](#docker-build-and-push)
5. [Database Migration](#database-migration)
6. [Verification](#verification)
7. [Common Deployment Patterns](#common-deployment-patterns)

---

## Prerequisites

Before you begin, ensure the following tools are installed and configured on your workstation.

### Required Tools

| Tool | Minimum Version | Install |
|---|---|---|
| Azure CLI | 2.55.0 | https://learn.microsoft.com/cli/azure/install-azure-cli |
| Terraform | 1.6.0 | https://developer.hashicorp.com/terraform/install |
| Docker Desktop | 24.0 | https://www.docker.com/products/docker-desktop |
| .NET SDK | 9.0 | https://dotnet.microsoft.com/download |
| Git | 2.40 | https://git-scm.com |

### Verify Tool Versions

```bash
az version
terraform version
docker version
dotnet --version
git --version
```

### Azure CLI Authentication

```bash
# Log in interactively
az login

# Verify the correct subscription is active
az account show

# If you need to switch subscriptions
az account set --subscription "<subscription-name-or-id>"

# For service principal login (CI/CD)
az login --service-principal \
  --username "$ARM_CLIENT_ID" \
  --password "$ARM_CLIENT_SECRET" \
  --tenant "$ARM_TENANT_ID"
```

### Required Azure Permissions

The identity performing the deployment needs the following roles at the subscription or
resource group level:

- `Contributor` — to create and manage resources
- `User Access Administrator` — to assign RBAC roles to managed identities
- `Key Vault Administrator` — to manage Key Vault secrets and policies

---

## Initial Azure Setup

### 1. Register Required Resource Providers

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.Web

# Verify registration status
az provider list --query "[?registrationState=='Registered'].namespace" -o tsv
```

### 2. Create Resource Group

```bash
# Define variables for consistency
RESOURCE_GROUP="rg-auth-framework-prod"
LOCATION="eastus2"
ENVIRONMENT="prod"

# Create the resource group
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --tags environment="$ENVIRONMENT" project="auth-framework" managed-by="terraform"

# Verify creation
az group show --name "$RESOURCE_GROUP" --output table
```

### 3. Create Terraform State Storage

The Terraform remote state backend requires an Azure Storage Account. This must be
created before running Terraform for the first time.

```bash
STATE_RG="rg-terraform-state"
STATE_SA="stterraformstate$(openssl rand -hex 4)"
STATE_CONTAINER="tfstate"

# Create the state resource group
az group create --name "$STATE_RG" --location "$LOCATION"

# Create the storage account (LRS is sufficient for state files)
az storage account create \
  --name "$STATE_SA" \
  --resource-group "$STATE_RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2

# Enable versioning to protect state files
az storage account blob-service-properties update \
  --account-name "$STATE_SA" \
  --resource-group "$STATE_RG" \
  --enable-versioning true

# Create the container
az storage container create \
  --name "$STATE_CONTAINER" \
  --account-name "$STATE_SA" \
  --auth-mode login

echo "Storage account name: $STATE_SA"
echo "Update terraform/environments/prod/backend.tf with this value."
```

---

## Terraform Deployment

### 1. Configure the Backend

Update `terraform/environments/prod/backend.tf` with the storage account name from the
previous step:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "<STATE_SA>"
    container_name       = "tfstate"
    key                  = "prod/terraform.tfstate"
  }
}
```

### 2. Prepare Variable Files

Copy the example variable file and fill in your values:

```bash
cp terraform/environments/prod/terraform.tfvars.example \
   terraform/environments/prod/terraform.tfvars
```

Edit `terraform.tfvars` and set at minimum:

```hcl
environment         = "prod"
location            = "eastus2"
resource_group_name = "rg-auth-framework-prod"
app_name            = "auth-framework"

postgres_admin_username = "pgadmin"
postgres_sku_name       = "GP_Standard_D2s_v3"
postgres_storage_mb     = 32768

app_service_sku_name    = "P1v3"
app_service_min_count   = 2
app_service_max_count   = 10

acr_sku                 = "Premium"
```

> **Security note:** Never commit `terraform.tfvars` to source control. It is listed in
> `.gitignore` by default.

### 3. Initialize Terraform

```bash
cd terraform/environments/prod

terraform init \
  -backend-config="resource_group_name=rg-terraform-state" \
  -backend-config="storage_account_name=$STATE_SA" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=prod/terraform.tfstate"
```

### 4. Plan the Deployment

```bash
terraform plan \
  -var-file="terraform.tfvars" \
  -out="prod.tfplan"
```

Review the plan output carefully. Pay attention to any resources marked with `~` (update),
`-/+` (replace), or `-` (destroy). Resources that will be destroyed and recreated (like
databases) require extra caution in production.

### 5. Apply the Deployment

```bash
terraform apply "prod.tfplan"
```

The full infrastructure deployment typically takes 15–25 minutes. PostgreSQL Flexible
Server provisioning is the longest step (~10 minutes).

### 6. Retrieve Outputs

```bash
# Show all outputs
terraform output

# Get specific values needed for subsequent steps
ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)
ACR_NAME=$(terraform output -raw acr_name)
APP_SERVICE_NAME=$(terraform output -raw app_service_name)
APP_URL=$(terraform output -raw app_service_default_hostname)

echo "ACR:        $ACR_LOGIN_SERVER"
echo "App:        $APP_SERVICE_NAME"
echo "URL:        https://$APP_URL"
```

---

## Docker Build and Push

### 1. Authenticate to ACR

```bash
# Using Azure CLI credentials (recommended for developer workstations)
az acr login --name "$ACR_NAME"

# Using admin credentials (not recommended for production)
az acr login \
  --name "$ACR_NAME" \
  --username "$(az acr credential show -n $ACR_NAME --query username -o tsv)" \
  --password "$(az acr credential show -n $ACR_NAME --query passwords[0].value -o tsv)"
```

### 2. Build the Docker Image

```bash
cd auth-framework-api

# Build with version tag derived from git
IMAGE_TAG=$(git rev-parse --short HEAD)
IMAGE_NAME="$ACR_LOGIN_SERVER/auth-framework-api"

docker build \
  --file Dockerfile \
  --tag "$IMAGE_NAME:$IMAGE_TAG" \
  --tag "$IMAGE_NAME:latest" \
  --build-arg BUILD_CONFIGURATION=Release \
  .
```

### 3. Push to ACR

```bash
docker push "$IMAGE_NAME:$IMAGE_TAG"
docker push "$IMAGE_NAME:latest"

# Verify the image is available in ACR
az acr repository show-tags \
  --name "$ACR_NAME" \
  --repository "auth-framework-api" \
  --orderby time_desc \
  --output table
```

### 4. Build via ACR Tasks (Alternative)

For CI/CD pipelines without local Docker access, use ACR Tasks to build remotely:

```bash
az acr build \
  --registry "$ACR_NAME" \
  --image "auth-framework-api:$IMAGE_TAG" \
  --file Dockerfile \
  .
```

---

## Database Migration

### 1. Allow Migration Access

Temporarily allow your current IP address to reach the PostgreSQL server:

```bash
MY_IP=$(curl -s https://api.ipify.org)
PG_SERVER_NAME=$(terraform output -raw postgres_server_name)

az postgres flexible-server firewall-rule create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PG_SERVER_NAME" \
  --rule-name "temp-migration-$(date +%Y%m%d%H%M)" \
  --start-ip-address "$MY_IP" \
  --end-ip-address "$MY_IP"
```

### 2. Retrieve the Connection String

```bash
PG_HOST=$(terraform output -raw postgres_server_fqdn)
PG_USER=$(terraform output -raw postgres_admin_username)

# Retrieve the password from Key Vault
KV_NAME=$(terraform output -raw key_vault_name)
PG_PASSWORD=$(az keyvault secret show \
  --vault-name "$KV_NAME" \
  --name "postgres-admin-password" \
  --query value -o tsv)

export ConnectionStrings__DefaultConnection="Host=$PG_HOST;Port=5432;Database=authdb;Username=$PG_USER;Password=$PG_PASSWORD;Ssl Mode=Require;Trust Server Certificate=false"
```

### 3. Run EF Core Migrations

```bash
cd auth-framework-api/src

# List pending migrations
dotnet ef migrations list \
  --project AuthFramework.Infrastructure \
  --startup-project AuthFramework.Api

# Apply migrations
dotnet ef database update \
  --project AuthFramework.Infrastructure \
  --startup-project AuthFramework.Api \
  --verbose
```

### 4. Remove Temporary Firewall Rule

```bash
az postgres flexible-server firewall-rule delete \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PG_SERVER_NAME" \
  --rule-name "temp-migration-$(date +%Y%m%d%H%M)" \
  --yes
```

---

## Verification

### 1. Health Check

```bash
APP_URL=$(terraform output -raw app_service_default_hostname)

# Wait for the app to start (up to 5 minutes after deployment)
for i in {1..30}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$APP_URL/health")
  echo "Attempt $i: HTTP $STATUS"
  [ "$STATUS" = "200" ] && break
  sleep 10
done
```

### 2. Verify App Service Configuration

```bash
az webapp config appsettings list \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --output table
```

### 3. Stream Logs

```bash
az webapp log tail \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"
```

### 4. Verify Database Connectivity

```bash
az postgres flexible-server connect \
  --name "$PG_SERVER_NAME" \
  --admin-user "$PG_USER" \
  --admin-password "$PG_PASSWORD" \
  --database-name "authdb" \
  --querytext "SELECT version();"
```

### 5. Verify Container Image Running

```bash
az webapp show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "siteConfig.linuxFxVersion" \
  --output tsv
```

---

## Common Deployment Patterns

### Blue/Green Deployment with Staging Slots

```bash
# Deploy to staging slot first
az webapp deployment slot swap \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_SERVICE_NAME" \
  --slot staging \
  --target-slot production

# Verify the swap succeeded
az webapp show \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "defaultHostName" -o tsv
```

### Rolling Back a Deployment

```bash
# Swap back to the previous version
az webapp deployment slot swap \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_SERVICE_NAME" \
  --slot production \
  --target-slot staging

# Or redeploy a specific image tag
az webapp config container set \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --docker-custom-image-name "$ACR_LOGIN_SERVER/auth-framework-api:<previous-tag>"

az webapp restart \
  --name "$APP_SERVICE_NAME" \
  --resource-group "$RESOURCE_GROUP"
```

### Environment Promotion (Dev → Staging → Prod)

```bash
# Promote the same image tag through environments — never rebuild
IMAGE_TAG="abc123f"

for ENV in dev staging prod; do
  echo "=== Deploying to $ENV ==="
  APP_NAME="app-auth-framework-$ENV"
  RG="rg-auth-framework-$ENV"

  az webapp config container set \
    --name "$APP_NAME" \
    --resource-group "$RG" \
    --docker-custom-image-name "$ACR_LOGIN_SERVER/auth-framework-api:$IMAGE_TAG"

  az webapp restart --name "$APP_NAME" --resource-group "$RG"

  # Wait for health check
  HOST=$(az webapp show -n "$APP_NAME" -g "$RG" --query defaultHostName -o tsv)
  sleep 30
  curl -sf "https://$HOST/health" && echo "$ENV: healthy" || echo "$ENV: FAILED"
done
```

### Automated CI/CD with Azure DevOps / GitHub Actions

The repository includes pipeline definitions. The general sequence is:

1. Build and test the .NET application
2. Build and push the Docker image to ACR with a unique tag
3. Run Terraform plan and apply (guarded by approval for production)
4. Deploy the new image tag to the staging slot
5. Run smoke tests against staging
6. Swap staging to production
7. Run post-deployment health checks

---

## Troubleshooting Deployment Issues

| Symptom | Likely Cause | Resolution |
|---|---|---|
| `az login` fails | Conditional access policy | Use device-code flow: `az login --use-device-code` |
| Terraform apply timeout | PostgreSQL provisioning slow | Increase `create_timeout` in provider config |
| Container fails to start | Missing env var or Key Vault reference | Check `az webapp log tail` output |
| 503 after deployment | App still starting | Wait 2–5 minutes; check health endpoint |
| ACR push 401 | Token expired | Re-run `az acr login --name $ACR_NAME` |
| Migration fails | Firewall not open | Verify IP allow rule; check VNet integration |

For deeper troubleshooting, see [AZURE-TROUBLESHOOTING.md](./AZURE-TROUBLESHOOTING.md).
