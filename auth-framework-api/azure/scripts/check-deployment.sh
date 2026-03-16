#!/usr/bin/env bash
set -euo pipefail

log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_warn()    { echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Verify the status of a deployed Auth Framework environment.

OPTIONS:
  -g, --resource-group  Resource group name [required]
  -n, --app-name        App Service name [required]
  -e, --environment     Environment (dev|staging|prod)
  -s, --subscription    Azure subscription ID
  -h, --help            Show this help
EOF
}

RESOURCE_GROUP=""
APP_NAME=""
ENVIRONMENT="dev"
SUBSCRIPTION=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -n|--app-name)       APP_NAME="$2";       shift 2 ;;
    -e|--environment)    ENVIRONMENT="$2";    shift 2 ;;
    -s|--subscription)   SUBSCRIPTION="$2";   shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *)                   log_error "Unknown: $1"; exit 1 ;;
  esac
done

[[ -z "$RESOURCE_GROUP" ]] && { log_error "--resource-group is required"; exit 1; }
[[ -z "$APP_NAME" ]]       && { log_error "--app-name is required";       exit 1; }

command -v az &>/dev/null || { log_error "Azure CLI not found"; exit 1; }

[[ -n "$SUBSCRIPTION" ]] && az account set --subscription "$SUBSCRIPTION"

OVERALL_STATUS=0

check_resource() {
  local resource_type="$1"
  local name="$2"
  local status="$3"
  local expected="$4"

  if [[ "$status" == "$expected" ]]; then
    log_success "$resource_type '$name': $status"
  else
    log_error "$resource_type '$name': $status (expected: $expected)"
    OVERALL_STATUS=1
  fi
}

log_info "=== Deployment Status Check: $RESOURCE_GROUP ==="

# App Service
APP_STATE=$(az webapp show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query state -o tsv 2>/dev/null || echo "NotFound")
check_resource "App Service" "$APP_NAME" "$APP_STATE" "Running"

# Staging slot
STAGING_STATE=$(az webapp show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --slot staging \
  --query state -o tsv 2>/dev/null || echo "NotFound")
log_info "App Service staging slot: $STAGING_STATE"

# HTTP health check
APP_URL=$(az webapp show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query defaultHostName -o tsv 2>/dev/null || echo "")

if [[ -n "$APP_URL" ]]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://${APP_URL}/health" --max-time 15 || echo "000")
  check_resource "Health endpoint" "https://${APP_URL}/health" "$HTTP_CODE" "200"
fi

# Container image deployed
CONTAINER_IMAGE=$(az webapp config container show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?name=='DOCKER_CUSTOM_IMAGE_NAME'].value" \
  -o tsv 2>/dev/null || echo "unknown")
log_info "Container image: $CONTAINER_IMAGE"

# Recent deployments
log_info "=== Recent Deployments ==="
az webapp deployment list \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --output table 2>/dev/null || log_warn "Could not retrieve deployment history"

echo ""
if [[ $OVERALL_STATUS -eq 0 ]]; then
  log_success "Deployment check PASSED"
else
  log_error "Deployment check FAILED"
fi
exit $OVERALL_STATUS
