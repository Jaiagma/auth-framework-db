#!/usr/bin/env bash
set -euo pipefail

log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Test database and service connectivity.

OPTIONS:
  -h, --pg-host        PostgreSQL FQDN [required]
  -u, --pg-user        PostgreSQL username [required]
  -p, --pg-password    PostgreSQL password (or set PGPASSWORD)
  -d, --database       Database name (default: authframework)
  --app-url            App Service URL to also test
  -H, --help           Show this help
EOF
}

PG_HOST=""
PG_USER=""
PG_PASSWORD="${PGPASSWORD:-}"
PG_DATABASE="authframework"
APP_URL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--pg-host)     PG_HOST="$2";     shift 2 ;;
    -u|--pg-user)     PG_USER="$2";     shift 2 ;;
    -p|--pg-password) PG_PASSWORD="$2"; shift 2 ;;
    -d|--database)    PG_DATABASE="$2"; shift 2 ;;
    --app-url)        APP_URL="$2";     shift 2 ;;
    -H|--help)        usage; exit 0 ;;
    *)                log_error "Unknown: $1"; exit 1 ;;
  esac
done

[[ -z "$PG_HOST" ]]  && { log_error "--pg-host is required"; exit 1; }
[[ -z "$PG_USER" ]]  && { log_error "--pg-user is required"; exit 1; }

command -v psql &>/dev/null || { log_error "psql not found"; exit 1; }

export PGPASSWORD="$PG_PASSWORD"
EXIT_CODE=0

log_info "=== PostgreSQL Connectivity Test ==="
log_info "Host: $PG_HOST, Database: $PG_DATABASE, User: $PG_USER"

# TCP connectivity
if nc -z -w5 "$PG_HOST" 5432 2>/dev/null; then
  log_success "TCP port 5432 reachable"
else
  log_error "Cannot reach $PG_HOST:5432"
  EXIT_CODE=1
fi

# PostgreSQL authentication
if psql -h "$PG_HOST" -U "$PG_USER" -d "$PG_DATABASE" \
    -c "SELECT current_database(), current_user, version();" \
    --no-password -q 2>/dev/null; then
  log_success "PostgreSQL authentication successful"
else
  log_error "PostgreSQL authentication failed"
  EXIT_CODE=1
fi

# Extensions check
if psql -h "$PG_HOST" -U "$PG_USER" -d "$PG_DATABASE" \
    -c "SELECT extname FROM pg_extension ORDER BY extname;" \
    --no-password -q 2>/dev/null; then
  log_success "Extensions query successful"
fi

# App Service check
if [[ -n "$APP_URL" ]]; then
  log_info "=== App Service Connectivity Test ==="
  APP_URL="${APP_URL%/}"
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${APP_URL}/health" --max-time 15 || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    log_success "App health endpoint: HTTP $HTTP_CODE"
  else
    log_error "App health endpoint: HTTP $HTTP_CODE"
    EXIT_CODE=1
  fi
fi

exit $EXIT_CODE
