#!/usr/bin/env bash
set -euo pipefail

log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_warn()    { echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Check health of deployed Auth Framework components.

OPTIONS:
  -a, --app-url         App Service base URL [required]
  -v, --vault-name      Key Vault name (to test access)
  -g, --resource-group  Resource group name
  -n, --app-name        App Service name
  --retries             Max retries for health check (default: 5)
  --timeout             Timeout per request in seconds (default: 30)
  -h, --help            Show this help
EOF
}

APP_URL=""
VAULT_NAME=""
RESOURCE_GROUP=""
APP_NAME=""
RETRIES=5
TIMEOUT=30
EXIT_CODE=0

while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--app-url)        APP_URL="$2";        shift 2 ;;
    -v|--vault-name)     VAULT_NAME="$2";     shift 2 ;;
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -n|--app-name)       APP_NAME="$2";       shift 2 ;;
    --retries)           RETRIES="$2";        shift 2 ;;
    --timeout)           TIMEOUT="$2";        shift 2 ;;
    -h|--help)           usage; exit 0 ;;
    *)                   log_error "Unknown: $1"; exit 1 ;;
  esac
done

[[ -z "$APP_URL" ]] && { log_error "--app-url is required"; exit 1; }

# Remove trailing slash
APP_URL="${APP_URL%/}"

check_http_endpoint() {
  local url="$1"
  local expected_code="${2:-200}"
  local description="$3"

  log_info "Checking: $description ($url)"
  for i in $(seq 1 "$RETRIES"); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      --max-time "$TIMEOUT" \
      --retry 0 \
      "$url" 2>/dev/null || echo "000")

    if [[ "$HTTP_CODE" == "$expected_code" ]]; then
      log_success "$description: HTTP $HTTP_CODE"
      return 0
    fi

    log_warn "Attempt $i/$RETRIES: HTTP $HTTP_CODE (expected $expected_code)"
    [[ $i -lt $RETRIES ]] && sleep 10
  done

  log_error "$description: Failed after $RETRIES attempts (last: HTTP $HTTP_CODE)"
  return 1
}

# 1. Health endpoint
log_info "=== App Service Health Check ==="
check_http_endpoint "${APP_URL}/health" "200" "Health endpoint" || EXIT_CODE=1

# 2. Ready endpoint (if exists)
check_http_endpoint "${APP_URL}/health/ready" "200" "Readiness endpoint" || {
  log_warn "Readiness endpoint not available (non-fatal)"
}

# 3. Key Vault access check
if [[ -n "$VAULT_NAME" ]]; then
  log_info "=== Key Vault Access Check ==="
  command -v az &>/dev/null && {
    SECRET_COUNT=$(az keyvault secret list \
      --vault-name "$VAULT_NAME" \
      --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$SECRET_COUNT" -gt 0 ]]; then
      log_success "Key Vault accessible: $SECRET_COUNT secrets found"
    else
      log_warn "Key Vault accessible but no secrets found"
    fi
  } || log_warn "Azure CLI not available; skipping Key Vault check"
fi

# 4. App Service state check
if [[ -n "$APP_NAME" && -n "$RESOURCE_GROUP" ]]; then
  log_info "=== App Service Status Check ==="
  command -v az &>/dev/null && {
    STATE=$(az webapp show \
      --name "$APP_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --query state -o tsv 2>/dev/null || echo "Unknown")
    if [[ "$STATE" == "Running" ]]; then
      log_success "App Service state: $STATE"
    else
      log_error "App Service state: $STATE (expected: Running)"
      EXIT_CODE=1
    fi
  } || log_warn "Azure CLI not available; skipping App Service state check"
fi

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
  log_success "All health checks passed!"
else
  log_error "One or more health checks failed!"
fi
exit $EXIT_CODE
