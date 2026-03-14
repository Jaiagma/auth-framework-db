#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Run Entity Framework Core database migrations.

OPTIONS:
  -s, --subscription    Azure subscription ID
  -g, --resource-group  Resource group name
  -e, --environment     Environment (dev|staging|prod)
  -v, --vault-name      Key Vault name (to fetch connection string)
  -c, --connection      Direct connection string (alternative to Key Vault)
  --dry-run             Show pending migrations without applying
  -h, --help            Show this help
EOF
}

SUBSCRIPTION=""
RESOURCE_GROUP=""
ENVIRONMENT=""
VAULT_NAME=""
CONNECTION_STRING="${ConnectionStrings__DefaultConnection:-}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--subscription)   SUBSCRIPTION="$2";   shift 2 ;;
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -e|--environment)    ENVIRONMENT="$2";    shift 2 ;;
    -v|--vault-name)     VAULT_NAME="$2";     shift 2 ;;
    -c|--connection)     CONNECTION_STRING="$2"; shift 2 ;;
    --dry-run)           DRY_RUN=true;         shift ;;
    -h|--help)           usage; exit 0 ;;
    *)                   log_error "Unknown: $1"; exit 1 ;;
  esac
done

command -v dotnet &>/dev/null || { log_error "dotnet CLI not found"; exit 1; }

# Fetch connection string from Key Vault if not provided directly
if [[ -z "$CONNECTION_STRING" && -n "$VAULT_NAME" ]]; then
  log_info "Fetching connection string from Key Vault: $VAULT_NAME"
  [[ -n "$SUBSCRIPTION" ]] && az account set --subscription "$SUBSCRIPTION"
  CONNECTION_STRING=$(az keyvault secret show \
    --vault-name "$VAULT_NAME" \
    --name "db-connection-string" \
    --query value -o tsv)
  log_success "Connection string retrieved"
fi

[[ -z "$CONNECTION_STRING" ]] && { log_error "Connection string required (--connection or --vault-name)"; exit 1; }

INFRA_PROJECT="${REPO_ROOT}/auth-framework-api/src/AuthFramework.Infrastructure"
API_PROJECT="${REPO_ROOT}/auth-framework-api/src/AuthFramework.Api/AuthFramework.Api.csproj"

log_info "Installing dotnet-ef tool..."
dotnet tool install --global dotnet-ef --ignore-failed-sources 2>/dev/null || true
export PATH="${PATH}:${HOME}/.dotnet/tools"

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "Pending migrations (dry run):"
  cd "$INFRA_PROJECT"
  dotnet ef migrations list \
    --startup-project "$API_PROJECT" \
    --connection "$CONNECTION_STRING" \
    --no-build
else
  log_info "Running database migrations..."
  cd "$INFRA_PROJECT"
  dotnet ef database update \
    --startup-project "$API_PROJECT" \
    --connection "$CONNECTION_STRING"
  log_success "Migrations applied successfully"
fi
