# 5-Minute Azure CLI Setup

## Prerequisites
- Azure CLI installed and logged in: `az login`
- Docker installed

## Steps

```bash
# 1. Set variables
RG="rg-authframework-dev"
LOCATION="eastus2"
APP="authframework-dev-api"
ACR="authframeworkdevacr"
KV="authframework-dev-kv"
PG="authframework-dev-psql"

# 2. Create resource group
az group create -n $RG -l $LOCATION

# 3. Create Key Vault and set secrets
az keyvault create -n $KV -g $RG -l $LOCATION
az keyvault secret set --vault-name $KV -n db-password --value "$(openssl rand -base64 24)"
az keyvault secret set --vault-name $KV -n jwt-secret-key --value "$(openssl rand -base64 48)"
az keyvault secret set --vault-name $KV -n encryption-key --value "$(openssl rand -hex 16)"

# 4. Create ACR
az acr create -n $ACR -g $RG --sku Basic --admin-enabled true

# 5. Create App Service Plan + Web App
az appservice plan create -n "${APP}-asp" -g $RG --is-linux --sku B2
az webapp create -n $APP -g $RG -p "${APP}-asp" -i "mcr.microsoft.com/appsvc/staticsite:latest"

# 6. Assign managed identity and grant KV access
az webapp identity assign -n $APP -g $RG
PID=$(az webapp identity show -n $APP -g $RG --query principalId -o tsv)
az keyvault set-policy -n $KV --object-id $PID --secret-permissions get list

# 7. Build and push Docker image
az acr login -n $ACR
docker build -t ${ACR}.azurecr.io/authframework-api:latest -f auth-framework-api/Dockerfile auth-framework-api/
docker push ${ACR}.azurecr.io/authframework-api:latest

# 8. Configure web app container
az webapp config container set -n $APP -g $RG \
  --docker-custom-image-name "${ACR}.azurecr.io/authframework-api:latest" \
  --docker-registry-server-url "https://${ACR}.azurecr.io"

echo "Done! https://${APP}.azurewebsites.net"
```
