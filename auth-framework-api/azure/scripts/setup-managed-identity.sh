#!/usr/bin/env bash
set -euo pipefail

log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Assign Key Vault and ACR roles to App Service managed identity.

OPTIONS:
  -a, --app-name       App Service name [required]
  -g, --resource-group Resource group name [required]
  -v, --vault-name     Key Vault name [required]
  -r, --acr-name       Container Registry name [required]
  -s, --subscription   Azure subscription ID
  -h, --help           Show this help
EOF
}

APP_NAME=""
RESOURCE_GROUP=""
VAULT_NAME=""
ACR_NAME=""
SUBSCRIPTION=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--app-name)       APP_NAME="$2";       shift 2 ;;
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -v|--vault-name)     VAULT_NAME="$2";     shift 2 ;;
    -r|--acr-name)       ACR_NAME="$2";       shift 2 ;;
    -s|--subscription)   SUBSCRIPTION="$2";   shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *)                   log_error "Unknown: $1"; exit 1 ;;
  esac
done

[[ -z "$APP_NAME" ]]       && { log_error "--app-name is required";       exit 1; }
[[ -z "$RESOURCE_GROUP" ]] && { log_error "--resource-group is required"; exit 1; }
[[ -z "$VAULT_NAME" ]]     && { log_error "--vault-name is required";     exit 1; }
[[ -z "$ACR_NAME" ]]       && { log_error "--acr-name is required";       exit 1; }

command -v az &>/dev/null || { log_error "Azure CLI not found"; exit 1; }

[[ -n "$SUBSCRIPTION" ]] && az account set --subscription "$SUBSCRIPTION"

# Get principal ID
log_info "Getting managed identity for App Service: $APP_NAME"
PRINCIPAL_ID=$(az webapp identity show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query principalId -o tsv 2>/dev/null || echo "")

if [[ -z "$PRINCIPAL_ID" ]]; then
  log_info "Managed identity not yet assigned; enabling SystemAssigned identity..."
  PRINCIPAL_ID=$(az webapp identity assign \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query principalId -o tsv)
fi
log_success "Principal ID: $PRINCIPAL_ID"

# Key Vault access policy
log_info "Granting Key Vault 'Get' and 'List' secrets access..."
az keyvault set-policy \
  --name "$VAULT_NAME" \
  --object-id "$PRINCIPAL_ID" \
  --secret-permissions get list \
  --output none
log_success "Key Vault access policy set"

# ACR pull role
log_info "Granting AcrPull role on $ACR_NAME..."
ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
az role assignment create \
  --assignee "$PRINCIPAL_ID" \
  --role AcrPull \
  --scope "$ACR_ID" \
  --output none 2>/dev/null || log_info "AcrPull already assigned"
log_success "AcrPull role assigned"

# Staging slot
STAGING_PRINCIPAL=$(az webapp identity show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --slot staging \
  --query principalId -o tsv 2>/dev/null || echo "")

if [[ -n "$STAGING_PRINCIPAL" ]]; then
  log_info "Setting up staging slot identity ($STAGING_PRINCIPAL)..."
  az keyvault set-policy \
    --name "$VAULT_NAME" \
    --object-id "$STAGING_PRINCIPAL" \
    --secret-permissions get list \
    --output none
  az role assignment create \
    --assignee "$STAGING_PRINCIPAL" \
    --role AcrPull \
    --scope "$ACR_ID" \
    --output none 2>/dev/null || true
  log_success "Staging slot identity configured"
fi

log_success "Managed identity setup complete"
