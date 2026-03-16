#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Auth Framework - Bicep Deployment Script
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

# Logging
log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_warn()    { echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Deploy Auth Framework infrastructure using Azure Bicep templates.

OPTIONS:
  -e, --environment    Deployment environment (dev|staging|prod) [required]
  -s, --subscription   Azure subscription ID [required]
  -g, --resource-group Resource group name [required]
  -l, --location       Azure region (default: eastus2)
  -p, --parameters     Parameters file path (default: parameters.json)
  --what-if            Run a what-if deployment (dry run)
  -h, --help           Show this help message

EXAMPLES:
  $(basename "$0") -e dev -s 00000000-0000-0000-0000-000000000000 -g rg-authframework-dev
  $(basename "$0") -e prod -s 00000000-... -g rg-authframework-prod --what-if

REQUIRED ENVIRONMENT VARIABLES (for secrets):
  DB_PASSWORD        PostgreSQL admin password
  JWT_SECRET_KEY     JWT signing secret (min 32 chars)
  ENCRYPTION_KEY     Data encryption key (32 chars)
EOF
}

# Defaults
ENVIRONMENT=""
SUBSCRIPTION=""
RESOURCE_GROUP=""
LOCATION="eastus2"
PARAMETERS_FILE="${SCRIPT_DIR}/parameters.json"
WHAT_IF=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -e|--environment)   ENVIRONMENT="$2";    shift 2 ;;
    -s|--subscription)  SUBSCRIPTION="$2";   shift 2 ;;
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -l|--location)      LOCATION="$2";       shift 2 ;;
    -p|--parameters)    PARAMETERS_FILE="$2"; shift 2 ;;
    --what-if)          WHAT_IF=true;         shift ;;
    -h|--help)          usage; exit 0 ;;
    *)                  log_error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Validate required args
[[ -z "$ENVIRONMENT" ]]    && { log_error "--environment is required"; usage; exit 1; }
[[ -z "$SUBSCRIPTION" ]]   && { log_error "--subscription is required"; usage; exit 1; }
[[ -z "$RESOURCE_GROUP" ]] && { log_error "--resource-group is required"; usage; exit 1; }

# Validate environment value
[[ "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]] || {
  log_error "Environment must be one of: dev, staging, prod"
  exit 1
}

# Check required tools
for tool in az; do
  command -v "$tool" &>/dev/null || { log_error "Required tool not found: $tool"; exit 1; }
done

# Validate secrets
[[ -z "${DB_PASSWORD:-}" ]]     && { log_error "DB_PASSWORD environment variable is required"; exit 1; }
[[ -z "${JWT_SECRET_KEY:-}" ]]  && { log_error "JWT_SECRET_KEY environment variable is required"; exit 1; }
[[ -z "${ENCRYPTION_KEY:-}" ]]  && { log_error "ENCRYPTION_KEY environment variable is required"; exit 1; }

log_info "Starting Bicep deployment"
log_info "  Environment:    $ENVIRONMENT"
log_info "  Subscription:   $SUBSCRIPTION"
log_info "  Resource Group: $RESOURCE_GROUP"
log_info "  Location:       $LOCATION"

# Login check
log_info "Verifying Azure login..."
az account show --subscription "$SUBSCRIPTION" --query id -o tsv &>/dev/null || {
  log_error "Not logged in to Azure. Run: az login"
  exit 1
}
az account set --subscription "$SUBSCRIPTION"
log_success "Azure login verified"

# Create resource group if it doesn't exist
log_info "Ensuring resource group exists: $RESOURCE_GROUP"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none || true
log_success "Resource group ready"

DEPLOY_CMD=(
  az deployment group
  --resource-group "$RESOURCE_GROUP"
  --template-file "${SCRIPT_DIR}/main.bicep"
  --parameters "${PARAMETERS_FILE}"
  --parameters
    "environment=${ENVIRONMENT}"
    "location=${LOCATION}"
    "dbPassword=${DB_PASSWORD}"
    "jwtSecretKey=${JWT_SECRET_KEY}"
    "encryptionKey=${ENCRYPTION_KEY}"
)

if [[ "$WHAT_IF" == "true" ]]; then
  log_info "Running what-if deployment..."
  "${DEPLOY_CMD[@]}" what-if
  log_success "What-if complete"
else
  log_info "Deploying Bicep templates..."
  DEPLOYMENT_NAME="authframework-${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)"
  "${DEPLOY_CMD[@]}" create \
    --name "$DEPLOYMENT_NAME" \
    --output table

  log_success "Deployment complete!"
  log_info "Fetching outputs..."
  az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DEPLOYMENT_NAME" \
    --query properties.outputs \
    -o table
fi
