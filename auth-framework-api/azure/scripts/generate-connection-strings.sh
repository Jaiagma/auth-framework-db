#!/usr/bin/env bash
set -euo pipefail

log_info() { echo "[INFO] $*"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Generate connection strings for different environments and frameworks.

OPTIONS:
  -h, --host        PostgreSQL FQDN [required]
  -d, --database    Database name (default: authframework)
  -u, --username    Username (default: authframework)
  -p, --password    Password (or set PGPASSWORD)
  -e, --env         Environment label (dev|staging|prod)
  -H, --help        Show this help
EOF
}

PG_HOST=""
PG_DATABASE="authframework"
PG_USERNAME="authframework"
PG_PASSWORD="${PGPASSWORD:-YOUR_PASSWORD}"
ENVIRONMENT="dev"

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--host)     PG_HOST="$2";     shift 2 ;;
    -d|--database) PG_DATABASE="$2"; shift 2 ;;
    -u|--username) PG_USERNAME="$2"; shift 2 ;;
    -p|--password) PG_PASSWORD="$2"; shift 2 ;;
    -e|--env)      ENVIRONMENT="$2"; shift 2 ;;
    -H|--help)     usage; exit 0 ;;
    *)             echo "Unknown: $1"; exit 1 ;;
  esac
done

[[ -z "$PG_HOST" ]] && { echo "ERROR: --host is required"; exit 1; }

SSL_MODE=$([[ "$ENVIRONMENT" == "prod" || "$ENVIRONMENT" == "staging" ]] && echo "VerifyFull" || echo "Require")

echo ""
echo "=== Connection Strings for: $ENVIRONMENT ($PG_HOST) ==="
echo ""

echo "--- .NET / Npgsql (appsettings.json) ---"
echo "\"DefaultConnection\": \"Host=${PG_HOST};Port=5432;Database=${PG_DATABASE};Username=${PG_USERNAME};Password=${PG_PASSWORD};SslMode=${SSL_MODE}\""

echo ""
echo "--- ADO.NET ---"
echo "Server=${PG_HOST};Port=5432;Database=${PG_DATABASE};User Id=${PG_USERNAME};Password=${PG_PASSWORD};Ssl Mode=${SSL_MODE};"

echo ""
echo "--- libpq / psql ---"
echo "postgresql://${PG_USERNAME}:${PG_PASSWORD}@${PG_HOST}:5432/${PG_DATABASE}?sslmode=${SSL_MODE,,}"

echo ""
echo "--- Environment variable ---"
echo "DATABASE_URL=postgresql://${PG_USERNAME}:${PG_PASSWORD}@${PG_HOST}:5432/${PG_DATABASE}?sslmode=${SSL_MODE,,}"

echo ""
echo "--- Azure App Service app setting ---"
echo "ConnectionStrings__DefaultConnection=Host=${PG_HOST};Port=5432;Database=${PG_DATABASE};Username=${PG_USERNAME};Password=${PG_PASSWORD};SslMode=${SSL_MODE}"

echo ""
echo "--- Key Vault reference (replace KV_NAME) ---"
echo "ConnectionStrings__DefaultConnection=@Microsoft.KeyVault(VaultName=KV_NAME;SecretName=db-connection-string)"
