#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Setup or rotate Key Vault secrets for Auth Framework.

OPTIONS:
  -v, --vault-name       Key Vault name [required]
  -g, --resource-group   Resource group name [required]
  -s, --subscription     Azure subscription ID
  --app-service-name     App Service name (to grant access)
  --rotate               Rotate existing secrets
  -h, --help             Show this help
EOF
}

VAULT_NAME=""
RESOURCE_GROUP=""
SUBSCRIPTION=""
APP_SERVICE_NAME=""
ROTATE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--vault-name)      VAULT_NAME="$2";       shift 2 ;;
    -g|--resource-group)  RESOURCE_GROUP="$2";   shift 2 ;;
    -s|--subscription)    SUBSCRIPTION="$2";     shift 2 ;;
    --app-service-name)   APP_SERVICE_NAME="$2"; shift 2 ;;
    --rotate)             ROTATE=true;            shift ;;
    -h|--help)            usage; exit 0 ;;
    *)                    log_error "Unknown: $1"; exit 1 ;;
  esac
done

[[ -z "$VAULT_NAME" ]]     && { log_error "--vault-name is required";     exit 1; }
[[ -z "$RESOURCE_GROUP" ]] && { log_error "--resource-group is required"; exit 1; }

command -v az &>/dev/null || { log_error "Azure CLI not found"; exit 1; }

if [[ -n "$SUBSCRIPTION" ]]; then
  az account set --subscription "$SUBSCRIPTION"
fi

set_secret() {
  local name="$1"
  local value="$2"
  local description="$3"

  if [[ "$ROTATE" == "false" ]]; then
    existing=$(az keyvault secret show --vault-name "$VAULT_NAME" --name "$name" --query value -o tsv 2>/dev/null || echo "")
    if [[ -n "$existing" ]]; then
      log_info "Secret '$name' already exists (use --rotate to overwrite)"
      return 0
    fi
  fi

  az keyvault secret set \
    --vault-name "$VAULT_NAME" \
    --name "$name" \
    --value "$value" \
    --description "$description" \
    --output none
  log_success "Secret '$name' set"
}

log_info "Setting Key Vault secrets in: $VAULT_NAME"

# DB Password
if [[ -n "${DB_PASSWORD:-}" ]]; then
  set_secret "db-password" "$DB_PASSWORD" "PostgreSQL administrator password"
else
  log_info "DB_PASSWORD not set; generating random password..."
  GENERATED_PW=$(openssl rand -base64 24 | tr -d '\n')
  set_secret "db-password" "$GENERATED_PW" "PostgreSQL administrator password (auto-generated)"
  log_info "Generated DB password stored in Key Vault"
fi

# JWT Secret Key
if [[ -n "${JWT_SECRET_KEY:-}" ]]; then
  set_secret "jwt-secret-key" "$JWT_SECRET_KEY" "JWT signing secret key"
else
  log_info "JWT_SECRET_KEY not set; generating random key..."
  GENERATED_JWT=$(openssl rand -base64 48)
  set_secret "jwt-secret-key" "$GENERATED_JWT" "JWT signing secret key (auto-generated)"
fi

# Encryption Key
if [[ -n "${ENCRYPTION_KEY:-}" ]]; then
  set_secret "encryption-key" "$ENCRYPTION_KEY" "Data encryption key"
else
  log_info "ENCRYPTION_KEY not set; generating random key..."
  GENERATED_ENC=$(openssl rand -hex 16)
  set_secret "encryption-key" "$GENERATED_ENC" "Data encryption key (auto-generated, 32 hex chars)"
fi

# Grant App Service access
if [[ -n "$APP_SERVICE_NAME" ]]; then
  log_info "Granting Key Vault access to App Service: $APP_SERVICE_NAME"
  PRINCIPAL_ID=$(az webapp identity show \
    --name "$APP_SERVICE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query principalId -o tsv)

  az keyvault set-policy \
    --name "$VAULT_NAME" \
    --object-id "$PRINCIPAL_ID" \
    --secret-permissions get list \
    --output none
  log_success "Access granted to $APP_SERVICE_NAME (principal: $PRINCIPAL_ID)"
fi

log_success "Key Vault setup complete: $VAULT_NAME"
