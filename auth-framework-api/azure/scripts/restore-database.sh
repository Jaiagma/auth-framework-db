#!/usr/bin/env bash
set -euo pipefail

log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_warn()    { echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Restore PostgreSQL database from Azure Blob Storage.

OPTIONS:
  -h, --host           PostgreSQL FQDN [required]
  -d, --database       Target database name (default: authframework)
  -u, --username       PostgreSQL username [required]
  -p, --password       PostgreSQL password (or set PGPASSWORD)
  -s, --storage-acct   Azure Storage account name [required]
  -c, --container      Blob container name (default: db-backups)
  -b, --blob-name      Specific blob to restore [required]
  --drop-existing      Drop and recreate the database before restore
  --list               List available backups instead of restoring
  -H, --help           Show this help
EOF
}

PG_HOST=""
PG_DATABASE="authframework"
PG_USERNAME=""
PG_PASSWORD="${PGPASSWORD:-}"
STORAGE_ACCOUNT=""
CONTAINER="db-backups"
BLOB_NAME=""
DROP_EXISTING=false
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--host)          PG_HOST="$2";         shift 2 ;;
    -d|--database)      PG_DATABASE="$2";     shift 2 ;;
    -u|--username)      PG_USERNAME="$2";     shift 2 ;;
    -p|--password)      PG_PASSWORD="$2";     shift 2 ;;
    -s|--storage-acct)  STORAGE_ACCOUNT="$2"; shift 2 ;;
    -c|--container)     CONTAINER="$2";       shift 2 ;;
    -b|--blob-name)     BLOB_NAME="$2";       shift 2 ;;
    --drop-existing)    DROP_EXISTING=true;    shift ;;
    --list)             LIST_ONLY=true;        shift ;;
    -H|--help)          usage; exit 0 ;;
    *)                  log_error "Unknown: $1"; exit 1 ;;
  esac
done

[[ -z "$STORAGE_ACCOUNT" ]] && { log_error "--storage-acct is required"; exit 1; }

# List mode
if [[ "$LIST_ONLY" == "true" ]]; then
  log_info "Available backups in $STORAGE_ACCOUNT/$CONTAINER:"
  az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --query "[].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}" \
    --output table \
    --auth-mode login
  exit 0
fi

[[ -z "$PG_HOST" ]]     && { log_error "--host is required";      exit 1; }
[[ -z "$PG_USERNAME" ]] && { log_error "--username is required";  exit 1; }
[[ -z "$BLOB_NAME" ]]   && { log_error "--blob-name is required"; exit 1; }

for tool in pg_restore psql gunzip az; do
  command -v "$tool" &>/dev/null || { log_error "Required tool not found: $tool"; exit 1; }
done

export PGPASSWORD="$PG_PASSWORD"

RESTORE_FILE="/tmp/restore_$(basename "$BLOB_NAME")"

log_warn "==================================================="
log_warn "  WARNING: This will overwrite database: $PG_DATABASE"
log_warn "  Source: $BLOB_NAME"
log_warn "==================================================="
read -r -p "Type 'RESTORE' to continue: " CONFIRM
[[ "$CONFIRM" == "RESTORE" ]] || { log_info "Restore cancelled."; exit 0; }

# Download backup
log_info "Downloading backup from Blob Storage..."
az storage blob download \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$CONTAINER" \
  --name "$BLOB_NAME" \
  --file "$RESTORE_FILE" \
  --output none \
  --auth-mode login
log_success "Downloaded: $(du -h "$RESTORE_FILE" | cut -f1)"

# Decompress if gzipped
if [[ "$RESTORE_FILE" == *.gz ]]; then
  log_info "Decompressing backup..."
  gunzip "$RESTORE_FILE"
  RESTORE_FILE="${RESTORE_FILE%.gz}"
fi

# Drop and recreate database if requested
if [[ "$DROP_EXISTING" == "true" ]]; then
  log_info "Dropping existing database: $PG_DATABASE"
  psql -h "$PG_HOST" -U "$PG_USERNAME" -d postgres \
    -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${PG_DATABASE}';" \
    --no-password
  psql -h "$PG_HOST" -U "$PG_USERNAME" -d postgres \
    -c "DROP DATABASE IF EXISTS \"${PG_DATABASE}\";" \
    --no-password
  psql -h "$PG_HOST" -U "$PG_USERNAME" -d postgres \
    -c "CREATE DATABASE \"${PG_DATABASE}\" WITH ENCODING='UTF8' LC_COLLATE='en_US.utf8' LC_CTYPE='en_US.utf8';" \
    --no-password
  log_success "Database recreated"
fi

# Restore
log_info "Restoring database..."
pg_restore \
  -h "$PG_HOST" \
  -U "$PG_USERNAME" \
  -d "$PG_DATABASE" \
  --no-owner \
  --no-acl \
  --exit-on-error \
  "$RESTORE_FILE"

rm -f "$RESTORE_FILE"
log_success "Database restore complete: $PG_DATABASE"
