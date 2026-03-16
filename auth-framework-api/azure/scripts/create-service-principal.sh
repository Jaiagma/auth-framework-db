#!/usr/bin/env bash
set -euo pipefail

log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_warn()    { echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Create an Azure Service Principal for GitHub Actions CI/CD.

OPTIONS:
  -n, --name          SP display name (default: authframework-github-actions)
  -s, --subscription  Azure subscription ID [required]
  -g, --resource-group Resource group to scope Contributor role
  --output-file       Write credentials JSON to file
  -h, --help          Show this help

OUTPUT:
  Prints AZURE_CREDENTIALS JSON to stdout (suitable for GitHub Actions secret)
EOF
}

SP_NAME="authframework-github-actions"
SUBSCRIPTION=""
RESOURCE_GROUP=""
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--name)           SP_NAME="$2";        shift 2 ;;
    -s|--subscription)   SUBSCRIPTION="$2";   shift 2 ;;
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --output-file)       OUTPUT_FILE="$2";    shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *)                   log_error "Unknown: $1"; exit 1 ;;
  esac
done

[[ -z "$SUBSCRIPTION" ]] && { log_error "--subscription is required"; exit 1; }

command -v az &>/dev/null || { log_error "Azure CLI not found"; exit 1; }

log_info "Setting subscription: $SUBSCRIPTION"
az account set --subscription "$SUBSCRIPTION"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Determine scope
if [[ -n "$RESOURCE_GROUP" ]]; then
  SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
  log_info "Scope: resource group ($RESOURCE_GROUP)"
else
  SCOPE="/subscriptions/${SUBSCRIPTION_ID}"
  log_info "Scope: subscription"
fi

log_info "Creating service principal: $SP_NAME"
CREDENTIALS=$(az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role Contributor \
  --scopes "$SCOPE" \
  --sdk-auth \
  --output json)

log_success "Service principal created"

# Also add AcrPush role if a resource group is specified
if [[ -n "$RESOURCE_GROUP" ]]; then
  SP_ID=$(echo "$CREDENTIALS" | python3 -c "import sys, json; print(json.load(sys.stdin)['clientId'])" 2>/dev/null || \
          echo "$CREDENTIALS" | grep -o '"clientId": "[^"]*"' | cut -d'"' -f4)

  log_info "Granting AcrPush role to service principal..."
  az role assignment create \
    --assignee "$SP_ID" \
    --role AcrPush \
    --scope "$SCOPE" \
    --output none 2>/dev/null || log_warn "AcrPush role assignment skipped (ACR may not exist yet)"
fi

echo ""
echo "============================================================"
echo "  AZURE_CREDENTIALS (add as GitHub Actions secret):"
echo "============================================================"
echo "$CREDENTIALS"
echo "============================================================"

if [[ -n "$OUTPUT_FILE" ]]; then
  echo "$CREDENTIALS" > "$OUTPUT_FILE"
  chmod 600 "$OUTPUT_FILE"
  log_success "Credentials saved to: $OUTPUT_FILE"
  log_warn "Keep this file secure and do not commit it to version control!"
fi

log_info ""
log_info "Required GitHub Actions secrets:"
log_info "  AZURE_CREDENTIALS          = (the JSON above)"
log_info "  AZURE_SUBSCRIPTION_ID      = $SUBSCRIPTION_ID"
log_info "  AZURE_TENANT_ID            = $(az account show --query tenantId -o tsv)"
log_info "  AZURE_CLIENT_ID            = $(echo "$CREDENTIALS" | grep -o '"clientId": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo '<see JSON above>')"
