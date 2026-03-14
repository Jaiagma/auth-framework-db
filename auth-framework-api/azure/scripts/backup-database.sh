#!/usr/bin/env bash
set -euo pipefail

log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Backup PostgreSQL database to Azure Blob Storage.

OPTIONS:
  -h, --host           PostgreSQL FQDN [required]
  -d, --database       Database name (default: authframework)
  -u, --username       PostgreSQL username [required]
  -p, --password       PostgreSQL password (or set PGPASSWORD)
  -s, --storage-acct   Azure Storage account name [required]
  -c, --container      Blob container name (default: db-backups)
  -e, --environment    Environment tag (dev|staging|prod)
  --retention-days     Days to retain backups (default: 30)
  -H, --help           Show this help
EOF
}

PG_HOST=""
PG_DATABASE="authframework"
PG_USERNAME=""
PG_PASSWORD="${PGPASSWORD:-}"
STORAGE_ACCOUNT=""
CONTAINER="db-backups"
ENVIRONMENT="prod"
RETENTION_DAYS=30

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--host)          PG_HOST="$2";        shift 2 ;;
    -d|--database)      PG_DATABASE="$2";    shift 2 ;;
    -u|--username)      PG_USERNAME="$2";    shift 2 ;;
    -p|--password)      PG_PASSWORD="$2";    shift 2 ;;
    -s|--storage-acct)  STORAGE_ACCOUNT="$2"; shift 2 ;;
    -c|--container)     CONTAINER="$2";      shift 2 ;;
    -e|--environment)   ENVIRONMENT="$2";    shift 2 ;;
    --retention-days)   RETENTION_DAYS="$2"; shift 2 ;;
    -H|--help)          usage; exit 0 ;;
    *)                  log_error "Unknown: $1"; exit 1 ;;
  esac
done

[[ -z "$PG_HOST" ]]         && { log_error "--host is required";         exit 1; }
[[ -z "$PG_USERNAME" ]]     && { log_error "--username is required";     exit 1; }
[[ -z "$STORAGE_ACCOUNT" ]] && { log_error "--storage-acct is required"; exit 1; }

for tool in pg_dump gzip az; do
  command -v "$tool" &>/dev/null || { log_error "Required tool not found: $tool"; exit 1; }
done

export PGPASSWORD="$PG_PASSWORD"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/tmp/${PG_DATABASE}_${ENVIRONMENT}_${TIMESTAMP}.dump"
COMPRESSED_FILE="${BACKUP_FILE}.gz"
BLOB_NAME="${ENVIRONMENT}/${PG_DATABASE}_${TIMESTAMP}.dump.gz"

log_info "Starting database backup: $PG_DATABASE"
log_info "Destination: $STORAGE_ACCOUNT/$CONTAINER/$BLOB_NAME"

# Dump database
log_info "Running pg_dump..."
pg_dump \
  -h "$PG_HOST" \
  -U "$PG_USERNAME" \
  -d "$PG_DATABASE" \
  --format=custom \
  --compress=0 \
  --no-owner \
  --no-acl \
  -f "$BACKUP_FILE"
log_success "Database dump complete: $(du -h "$BACKUP_FILE" | cut -f1)"

# Compress
log_info "Compressing backup..."
gzip -9 "$BACKUP_FILE"
log_success "Compressed: $(du -h "$COMPRESSED_FILE" | cut -f1)"

# Upload to Azure Blob Storage
log_info "Uploading to Azure Blob Storage..."
az storage blob upload \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$CONTAINER" \
  --name "$BLOB_NAME" \
  --file "$COMPRESSED_FILE" \
  --overwrite \
  --output none \
  --auth-mode login

log_success "Backup uploaded: $BLOB_NAME"

# Clean up local temp file
rm -f "$COMPRESSED_FILE"
log_info "Local temp file removed"

# Remove old backups
log_info "Removing backups older than $RETENTION_DAYS days..."
CUTOFF_DATE=$(date -d "${RETENTION_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
              date -v-${RETENTION_DAYS}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")

if [[ -z "$CUTOFF_DATE" ]]; then
  log_warn "Could not determine cutoff date; skipping retention cleanup"
else
  az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --prefix "${ENVIRONMENT}/" \
    --query "[?properties.lastModified < '${CUTOFF_DATE}'].name" \
    -o tsv \
    --auth-mode login | while read -r blob; do
      az storage blob delete \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$CONTAINER" \
        --name "$blob" \
        --auth-mode login \
        --output none
      log_info "Deleted old backup: $blob"
    done
fi

log_success "Backup complete: $BLOB_NAME"
