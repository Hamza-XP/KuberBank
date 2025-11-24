#!/bin/bash
# ================================================================
# KuberBank Database Restore Script
# Description: Restore PostgreSQL database from backup
# Usage: ./restore.sh <backup_file> [options]
# ================================================================

set -e
set -u
set -o pipefail

# ================================================================
# CONFIGURATION
# ================================================================

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-kuberbank}"
DB_USER="${DB_USER:-bankuser}"
DB_PASSWORD="${DB_PASSWORD:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ================================================================
# FUNCTIONS
# ================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

usage() {
    cat << EOF
KuberBank Database Restore Script

Usage: $0 <backup_file> [OPTIONS]

Arguments:
    backup_file             Path to backup file (local or S3 URL)

Options:
    -h, --help              Show this help message
    -f, --force             Force restore without confirmation
    -d, --drop              Drop existing database
    --no-verify             Skip backup verification

Examples:
    $0 kuberbank_backup_20250125_120000.sql.gz
    $0 s3://bucket/backups/kuberbank_backup_20250125_120000.sql.gz
    $0 backup.sql.gz --force --drop

EOF
    exit 0
}

confirm_restore() {
    if [ "$FORCE_RESTORE" = "true" ]; then
        return 0
    fi
    
    warning "=========================================="
    warning "WARNING: Database Restore Operation"
    warning "=========================================="
    warning "This will restore the database: $DB_NAME"
    warning "Host: $DB_HOST:$DB_PORT"
    warning "Backup: $BACKUP_FILE"
    warning ""
    warning "All current data will be LOST!"
    warning "=========================================="
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log "Restore cancelled by user"
        exit 0
    fi
}

check_dependencies() {
    log "Checking dependencies..."
    
    local missing_deps=()
    
    command -v psql >/dev/null 2>&1 || missing_deps+=("psql")
    command -v gunzip >/dev/null 2>&1 || missing_deps+=("gunzip")
    
    if [[ "$BACKUP_FILE" == s3://* ]]; then
        command -v aws >/dev/null 2>&1 || missing_deps+=("aws-cli")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    log "All dependencies satisfied"
}

download_from_s3() {
    if [[ ! "$BACKUP_FILE" == s3://* ]]; then
        return 0
    fi
    
    log "Downloading backup from S3..."
    
    local temp_file="/tmp/kuberbank_restore_$(date +%s).sql.gz"
    
    if aws s3 cp "$BACKUP_FILE" "$temp_file" ${S3_ENDPOINT:+--endpoint-url $S3_ENDPOINT}; then
        BACKUP_FILE="$temp_file"
        TEMP_BACKUP="true"
        log "Downloaded to: $temp_file"
    else
        error "Failed to download from S3"
        exit 1
    fi
}

verify_backup() {
    if [ "$VERIFY_BACKUP" = "false" ]; then
        return 0
    fi
    
    log "Verifying backup file..."
    
    if [ ! -f "$BACKUP_FILE" ]; then
        error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi
    
    # Test if it's a valid gzip file
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        if ! gunzip -t "$BACKUP_FILE" 2>/dev/null; then
            error "Backup file is not a valid gzip file"
            exit 1
        fi
    fi
    
    local file_size=$(du -h "$BACKUP_FILE" | cut -f1)
    log "Backup file size: $file_size"
    log "Backup file verified"
}

test_db_connection() {
    log "Testing database connection..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT 1" >/dev/null 2>&1; then
        log "Database connection successful"
    else
        error "Failed to connect to database"
        exit 1
    fi
}

create_pre_restore_backup() {
    log "Creating pre-restore backup..."
    
    local backup_dir="/tmp"
    local backup_file="${backup_dir}/kuberbank_pre_restore_$(date +%Y%m%d_%H%M%S).sql.gz"
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" 2>/dev/null | gzip > "$backup_file"; then
        log "Pre-restore backup created: $backup_file"
        echo "$backup_file" > /tmp/kuberbank_last_backup.txt
    else
        warning "Pre-restore backup failed (database may not exist)"
    fi
}

terminate_connections() {
    log "Terminating existing database connections..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();
    " >/dev/null 2>&1 || true
    
    log "Connections terminated"
}

drop_database() {
    if [ "$DROP_DATABASE" != "true" ]; then
        return 0
    fi
    
    log "Dropping existing database..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    terminate_connections
    
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>&1; then
        log "Database dropped"
    else
        error "Failed to drop database"
        exit 1
    fi
}

create_database() {
    log "Creating database..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "
        CREATE DATABASE $DB_NAME
        WITH OWNER = $DB_USER
        ENCODING = 'UTF8'
        LC_COLLATE = 'en_US.UTF-8'
        LC_CTYPE = 'en_US.UTF-8';
    " 2>&1 || warning "Database may already exist"
    
    log "Database ready"
}

restore_backup() {
    log "Restoring database from backup..."
    log "This may take a while..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    # Decompress and restore
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        gunzip -c "$BACKUP_FILE" | \
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            --set ON_ERROR_STOP=off \
            -v ON_ERROR_STOP=1 2>&1 | \
        grep -v "^ERROR:" || true
    else
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -f "$BACKUP_FILE" \
            --set ON_ERROR_STOP=off \
            -v ON_ERROR_STOP=1 2>&1 | \
        grep -v "^ERROR:" || true
    fi
    
    log "Restore completed"
}

verify_restore() {
    log "Verifying restored database..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    # Check tables
    local table_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
    
    if [ "$table_count" -gt 0 ]; then
        log "Found $table_count tables"
    else
        error "No tables found after restore"
        exit 1
    fi
    
    # Check records
    local user_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | tr -d ' ') || echo "0"
    
    local account_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -c "SELECT COUNT(*) FROM accounts;" 2>/dev/null | tr -d ' ') || echo "0"
    
    log "Users: $user_count"
    log "Accounts: $account_count"
    log "Database verification successful"
}

cleanup() {
    if [ "$TEMP_BACKUP" = "true" ] && [ -f "$BACKUP_FILE" ]; then
        log "Cleaning up temporary files..."
        rm -f "$BACKUP_FILE"
    fi
}

# ================================================================
# MAIN SCRIPT
# ================================================================

main() {
    log "================================================================"
    log "KuberBank Database Restore Starting..."
    log "================================================================"
    
    # Confirm restore
    confirm_restore
    
    # Check dependencies
    check_dependencies
    
    # Download from S3 if needed
    download_from_s3
    
    # Verify backup file
    verify_backup
    
    # Test database connection
    test_db_connection
    
    # Create pre-restore backup
    create_pre_restore_backup
    
    # Drop database if requested
    drop_database
    
    # Create database
    create_database
    
    # Restore backup
    restore_backup
    
    # Verify restore
    verify_restore
    
    # Cleanup
    cleanup
    
    log "================================================================"
    log "Database restored successfully!"
    log "Database: $DB_NAME"
    log "Host: $DB_HOST:$DB_PORT"
    log "================================================================"
}

# ================================================================
# PARSE ARGUMENTS
# ================================================================

if [ $# -eq 0 ]; then
    usage
fi

BACKUP_FILE=""
FORCE_RESTORE="false"
DROP_DATABASE="false"
VERIFY_BACKUP="true"
TEMP_BACKUP="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -f|--force)
            FORCE_RESTORE="true"
            shift
            ;;
        -d|--drop)
            DROP_DATABASE="true"
            shift
            ;;
        --no-verify)
            VERIFY_BACKUP="false"
            shift
            ;;
        -*)
            error "Unknown option: $1"
            usage
            ;;
        *)
            BACKUP_FILE="$1"
            shift
            ;;
    esac
done

if [ -z "$BACKUP_FILE" ]; then
    error "Backup file not specified"
    usage
fi

# Run main function
trap cleanup EXIT
main

exit 0