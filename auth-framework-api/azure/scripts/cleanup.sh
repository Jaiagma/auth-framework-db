#!/usr/bin/env bash
set -euo pipefail

log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_warn()    { echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Delete Auth Framework Azure resources (USE WITH CAUTION).

OPTIONS:
  -g, --resource-group  Resource group to delete [required]
  -s, --subscription    Azure subscription ID
  --force               Skip confirmation prompt
  --purge-key-vault     Also purge soft-deleted Key Vault (permanent)
  -h, --help            Show this help
EOF
}

RESOURCE_GROUP=""
SUBSCRIPTION=""
FORCE=false
PURGE_KV=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -s|--subscription)   SUBSCRIPTION="$2";   shift 2 ;;
    --force)             FORCE=true;           shift ;;
    --purge-key-vault)   PURGE_KV=true;        shift ;;
    -h|--help)           usage; exit 0 ;;
    *)                   log_error "Unknown: $1"; exit 1 ;;
  esac
done

[[ -z "$RESOURCE_GROUP" ]] && { log_error "--resource-group is required"; exit 1; }

command -v az &>/dev/null || { log_error "Azure CLI not found"; exit 1; }

[[ -n "$SUBSCRIPTION" ]] && az account set --subscription "$SUBSCRIPTION"

# Verify resource group exists
az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null || {
  log_error "Resource group not found: $RESOURCE_GROUP"
  exit 1
}

log_warn "======================================================="
log_warn "  WARNING: This will DELETE all resources in:"
log_warn "  Resource Group: $RESOURCE_GROUP"
log_warn "  This action CANNOT be undone!"
log_warn "======================================================="

if [[ "$FORCE" == "false" ]]; then
  read -r -p "Type the resource group name to confirm deletion: " CONFIRM
  [[ "$CONFIRM" == "$RESOURCE_GROUP" ]] || { log_info "Cleanup cancelled."; exit 0; }
fi

# Get Key Vault names before deletion (for optional purge)
KV_NAMES=$(az keyvault list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].name" -o tsv 2>/dev/null || echo "")

log_info "Deleting resource group: $RESOURCE_GROUP"
az group delete \
  --name "$RESOURCE_GROUP" \
  --yes \
  --no-wait
log_info "Deletion initiated (running in background)"

# Wait for completion
log_info "Waiting for deletion to complete..."
while az group show --name "$RESOURCE_GROUP" --output none 2>/dev/null; do
  log_info "Still deleting..."
  sleep 30
done
log_info "Resource group deleted"

# Purge Key Vaults if requested
if [[ "$PURGE_KV" == "true" && -n "$KV_NAMES" ]]; then
  log_warn "Purging soft-deleted Key Vaults (permanent)..."
  while IFS= read -r kv_name; do
    if [[ -n "$kv_name" ]]; then
      az keyvault purge --name "$kv_name" --no-wait 2>/dev/null || \
        log_warn "Could not purge Key Vault: $kv_name (may already be purged)"
    fi
  done <<< "$KV_NAMES"
fi

log_info "Cleanup complete: $RESOURCE_GROUP"
