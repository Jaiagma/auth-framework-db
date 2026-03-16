# GitHub Actions Setup (5 Minutes)

## Prerequisites
- Azure subscription with Contributor access
- GitHub repository with Actions enabled

## Step 1: Create Service Principal

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
az ad sp create-for-rbac \
  --name "authframework-github-actions" \
  --role Contributor \
  --scopes "/subscriptions/${SUBSCRIPTION_ID}" \
  --sdk-auth
```
Copy the full JSON output.

## Step 2: Add GitHub Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret**:

| Secret Name | Value |
|---|---|
| `AZURE_CREDENTIALS` | Full JSON from Step 1 |
| `AZURE_SUBSCRIPTION_ID` | Your subscription ID |
| `AZURE_TENANT_ID` | Your tenant ID |
| `AZURE_CLIENT_ID` | clientId from JSON |
| `AZURE_CLIENT_SECRET` | clientSecret from JSON |
| `ACR_LOGIN_SERVER` | `yourname.azurecr.io` |
| `ACR_USERNAME` | ACR admin username |
| `ACR_PASSWORD` | ACR admin password |
| `APP_SERVICE_NAME` | `authframework-prod-api` |
| `RESOURCE_GROUP` | `rg-authframework-prod` |
| `KEY_VAULT_NAME` | `authframework-prod-kv` |
| `TF_STATE_RESOURCE_GROUP` | Resource group for TF state storage |
| `TF_STATE_STORAGE_ACCOUNT` | Storage account for TF state |

## Step 3: Trigger Deployment

Push to `main` to trigger `azure-deploy.yml`, or manually:
```
GitHub → Actions → Azure Deploy → Run workflow
```

## Step 4: Monitor
Watch the workflow run in **Actions** tab. Jobs execute in order:
1. build-and-test → 2. build-and-push-image → 3. deploy-infrastructure → 4. run-migrations → 5. deploy-app → 6. smoke-test
