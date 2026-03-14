#!/usr/bin/env bash
set -euo pipefail

log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Configure PostgreSQL extensions, roles and run schema files.

OPTIONS:
  -h, --host           PostgreSQL server FQDN [required]
  -d, --database       Database name (default: authframework)
  -u, --username       Admin username [required]
  -p, --password       Admin password (or set PGPASSWORD)
  --schema-dir         Directory containing SQL schema files
  --skip-extensions    Skip extension creation
  --skip-roles         Skip role creation
  -H, --help           Show this help
EOF
}

PG_HOST=""
PG_DATABASE="authframework"
PG_USERNAME=""
PG_PASSWORD="${PGPASSWORD:-}"
SCHEMA_DIR=""
SKIP_EXTENSIONS=false
SKIP_ROLES=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--host)           PG_HOST="$2";       shift 2 ;;
    -d|--database)       PG_DATABASE="$2";   shift 2 ;;
    -u|--username)       PG_USERNAME="$2";   shift 2 ;;
    -p|--password)       PG_PASSWORD="$2";   shift 2 ;;
    --schema-dir)        SCHEMA_DIR="$2";    shift 2 ;;
    --skip-extensions)   SKIP_EXTENSIONS=true; shift ;;
    --skip-roles)        SKIP_ROLES=true;     shift ;;
    -H|--help)           usage; exit 0 ;;
    *)                   log_error "Unknown: $1"; exit 1 ;;
  esac
done

[[ -z "$PG_HOST" ]]     && { log_error "--host is required";     exit 1; }
[[ -z "$PG_USERNAME" ]] && { log_error "--username is required"; exit 1; }

command -v psql &>/dev/null || { log_error "psql not found. Install postgresql-client."; exit 1; }

export PGPASSWORD="$PG_PASSWORD"

run_sql() {
  local sql="$1"
  psql -h "$PG_HOST" -U "$PG_USERNAME" -d "$PG_DATABASE" -c "$sql" --no-password
}

run_sql_file() {
  local file="$1"
  log_info "Running SQL file: $file"
  psql -h "$PG_HOST" -U "$PG_USERNAME" -d "$PG_DATABASE" -f "$file" --no-password
}

# Test connectivity
log_info "Testing connectivity to $PG_HOST..."
psql -h "$PG_HOST" -U "$PG_USERNAME" -d "postgres" -c "SELECT version();" --no-password > /dev/null
log_success "Connected to PostgreSQL"

# Create extensions
if [[ "$SKIP_EXTENSIONS" == "false" ]]; then
  log_info "Creating extensions..."
  for ext in "uuid-ossp" "pgcrypto" "pg_trgm" "btree_gin"; do
    run_sql "CREATE EXTENSION IF NOT EXISTS \"${ext}\";"
    log_success "Extension ready: $ext"
  done
fi

# Create roles
if [[ "$SKIP_ROLES" == "false" ]]; then
  log_info "Creating application roles..."
  run_sql "DO \$\$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authframework_app') THEN
      CREATE ROLE authframework_app LOGIN;
    END IF;
  END \$\$;"

  run_sql "GRANT CONNECT ON DATABASE \"${PG_DATABASE}\" TO authframework_app;"
  run_sql "GRANT USAGE ON SCHEMA public TO authframework_app;"
  run_sql "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authframework_app;"
  run_sql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authframework_app;"
  run_sql "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authframework_app;"
  run_sql "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO authframework_app;"
  log_success "Roles configured"
fi

# Run schema files
if [[ -n "$SCHEMA_DIR" && -d "$SCHEMA_DIR" ]]; then
  log_info "Running schema files from: $SCHEMA_DIR"
  for sql_file in "${SCHEMA_DIR}"/*.sql; do
    [[ -f "$sql_file" ]] && run_sql_file "$sql_file"
  done
  log_success "Schema files executed"
fi

log_success "PostgreSQL configuration complete"
