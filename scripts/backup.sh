#!/bin/bash
# ================================================================
# KuberBank Database Backup Script
# Description: Backup PostgreSQL database to local and S3
# Usage: ./backup.sh [options]
# ================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# ================================================================
# CONFIGURATION
# ================================================================

# Database configuration (can be overridden by environment variables)
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-kuberbank}"
DB_USER="${DB_USER:-bankuser}"
DB_PASSWORD="${DB_PASSWORD:-}"

# Backup configuration
BACKUP_DIR="${BACKUP_DIR:-/tmp/kuberbank_backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-9}"
DATE_FORMAT="%Y%m%d_%H%M%S"
TIMESTAMP=$(date +"$DATE_FORMAT")
BACKUP_FILENAME="kuberbank_backup_${TIMESTAMP}.sql.gz"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

# S3 configuration (optional)
S3_ENABLED="${S3_ENABLED:-false}"
S3_BUCKET="${S3_BUCKET:-kuberbank-backups}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_REGION="${S3_REGION:-us-east-1}"

# Notification configuration
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
EMAIL_TO="${EMAIL_TO:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
KuberBank Database Backup Script

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -d, --dir DIR           Backup directory (default: /tmp/kuberbank_backups)
    -r, --retention DAYS    Retention period in days (default: 30)
    -s, --s3                Enable S3 upload
    -t, --test              Test mode (no actual backup)
    -v, --verbose           Verbose output

Environment Variables:
    DB_HOST                 Database host
    DB_PORT                 Database port
    DB_NAME                 Database name
    DB_USER                 Database user
    DB_PASSWORD             Database password
    S3_BUCKET               S3 bucket name
    S3_ENDPOINT             S3 endpoint URL
    AWS_ACCESS_KEY_ID       AWS access key
    AWS_SECRET_ACCESS_KEY   AWS secret key

Examples:
    $0                      # Basic backup
    $0 -s                   # Backup and upload to S3
    $0 -d /backups -r 60    # Custom directory with 60-day retention

EOF
    exit 0
}

check_dependencies() {
    log "Checking dependencies..."
    
    local missing_deps=()
    
    command -v pg_dump >/dev/null 2>&1 || missing_deps+=("pg_dump")
    command -v gzip >/dev/null 2>&1 || missing_deps+=("gzip")
    
    if [ "$S3_ENABLED" = "true" ]; then
        command -v aws >/dev/null 2>&1 || missing_deps+=("aws-cli")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing dependencies: ${missing_deps[*]}"
        error "Please install missing dependencies and try again"
        exit 1
    fi
    
    log "All dependencies satisfied"
}

test_db_connection() {
    log "Testing database connection..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" >/dev/null 2>&1; then
        log "Database connection successful"
    else
        error "Failed to connect to database"
        error "Host: $DB_HOST, Port: $DB_PORT, Database: $DB_NAME, User: $DB_USER"
        exit 1
    fi
}

create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log "Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi
}

perform_backup() {
    log "Starting database backup..."
    log "Database: $DB_NAME@$DB_HOST:$DB_PORT"
    log "Backup file: $BACKUP_PATH"
    
    export PGPASSWORD="$DB_PASSWORD"
    
    # Perform backup with progress
    if pg_dump \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        --verbose \
        --format=plain \
        --no-owner \
        --no-acl \
        --clean \
        --if-exists \
        | gzip -"$COMPRESSION_LEVEL" > "$BACKUP_PATH"; then
        
        log "Backup completed successfully"
    else
        error "Backup failed"
        exit 1
    fi
    
    # Get backup size
    BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
    log "Backup size: $BACKUP_SIZE"
    
    # Verify backup
    if [ -f "$BACKUP_PATH" ] && [ -s "$BACKUP_PATH" ]; then
        log "Backup file verified"
    else
        error "Backup file is empty or does not exist"
        exit 1
    fi
}

upload_to_s3() {
    if [ "$S3_ENABLED" != "true" ]; then
        return 0
    fi
    
    log "Uploading backup to S3..."
    log "Bucket: s3://$S3_BUCKET/backups/"
    
    local s3_path="s3://${S3_BUCKET}/backups/${BACKUP_FILENAME}"
    local aws_opts="--region $S3_REGION"
    
    if [ -n "$S3_ENDPOINT" ]; then
        aws_opts="$aws_opts --endpoint-url $S3_ENDPOINT"
    fi
    
    if aws s3 cp "$BACKUP_PATH" "$s3_path" $aws_opts; then
        log "S3 upload successful"
        
        # Create metadata file
        local metadata_file="${BACKUP_DIR}/backup_metadata.json"
        cat > "$metadata_file" << EOF
{
    "timestamp": "${TIMESTAMP}",
    "filename": "${BACKUP_FILENAME}",
    "size": "${BACKUP_SIZE}",
    "database": "${DB_NAME}",
    "host": "${DB_HOST}",
    "s3_path": "${s3_path}"
}
EOF
        
        # Upload metadata
        aws s3 cp "$metadata_file" "s3://${S3_BUCKET}/backups/latest.json" $aws_opts
        
    else
        error "S3 upload failed"
        return 1
    fi
}

cleanup_old_backups() {
    log "Cleaning up backups older than $RETENTION_DAYS days..."
    
    # Local cleanup
    local deleted_count=0
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((deleted_count++))
    done < <(find "$BACKUP_DIR" -name "kuberbank_backup_*.sql.gz" -type f -mtime +"$RETENTION_DAYS" -print0)
    
    if [ $deleted_count -gt 0 ]; then
        log "Deleted $deleted_count old local backup(s)"
    else
        log "No old local backups to delete"
    fi
    
    # S3 cleanup
    if [ "$S3_ENABLED" = "true" ]; then
        log "Cleaning up old S3 backups..."
        
        local cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y%m%d)
        local aws_opts="--region $S3_REGION"
        
        if [ -n "$S3_ENDPOINT" ]; then
            aws_opts="$aws_opts --endpoint-url $S3_ENDPOINT"
        fi
        
        aws s3 ls "s3://${S3_BUCKET}/backups/" $aws_opts | \
        awk '{print $4}' | \
        grep "kuberbank_backup_" | \
        while read -r backup; do
            backup_date=$(echo "$backup" | sed 's/kuberbank_backup_\([0-9]\{8\}\).*/\1/')
            if [ "$backup_date" -lt "$cutoff_date" ]; then
                log "Deleting old S3 backup: $backup"
                aws s3 rm "s3://${S3_BUCKET}/backups/${backup}" $aws_opts
            fi
        done
    fi
}

send_notification() {
    local status=$1
    local message=$2
    
    # Slack notification
    if [ -n "$SLACK_WEBHOOK" ]; then
        local emoji="✅"
        local color="good"
        
        if [ "$status" != "success" ]; then
            emoji="❌"
            color="danger"
        fi
        
        curl -X POST "$SLACK_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "{
                \"text\": \"$emoji KuberBank Backup $status\",
                \"attachments\": [{
                    \"color\": \"$color\",
                    \"text\": \"$message\",
                    \"fields\": [
                        {\"title\": \"Database\", \"value\": \"$DB_NAME\", \"short\": true},
                        {\"title\": \"Timestamp\", \"value\": \"$TIMESTAMP\", \"short\": true},
                        {\"title\": \"Size\", \"value\": \"$BACKUP_SIZE\", \"short\": true}
                    ]
                }]
            }" >/dev/null 2>&1
    fi
    
    # Email notification (requires sendmail or similar)
    if [ -n "$EMAIL_TO" ]; then
        local subject="KuberBank Backup $status - $TIMESTAMP"
        echo "$message" | mail -s "$subject" "$EMAIL_TO" 2>/dev/null || true
    fi
}

generate_report() {
    log "Generating backup report..."
    
    local report_file="${BACKUP_DIR}/backup_report_${TIMESTAMP}.txt"
    
    cat > "$report_file" << EOF
================================================================
KuberBank Database Backup Report
================================================================

Timestamp: $(date)
Database: $DB_NAME
Host: $DB_HOST:$DB_PORT
User: $DB_USER

Backup Details:
- Filename: $BACKUP_FILENAME
- Path: $BACKUP_PATH
- Size: $BACKUP_SIZE
- Compression: Level $COMPRESSION_LEVEL

S3 Upload: $([ "$S3_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")
$([ "$S3_ENABLED" = "true" ] && echo "- Bucket: s3://$S3_BUCKET/backups/")

Retention: $RETENTION_DAYS days

Status: SUCCESS

================================================================
EOF
    
    cat "$report_file"
}

# ================================================================
# MAIN SCRIPT
# ================================================================

main() {
    log "================================================================"
    log "KuberBank Database Backup Starting..."
    log "================================================================"
    
    # Check dependencies
    check_dependencies
    
    # Test database connection
    test_db_connection
    
    # Create backup directory
    create_backup_dir
    
    # Perform backup
    perform_backup
    
    # Upload to S3 if enabled
    if [ "$S3_ENABLED" = "true" ]; then
        upload_to_s3
    fi
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Generate report
    generate_report
    
    # Send notification
    send_notification "success" "Backup completed successfully. Size: $BACKUP_SIZE"
    
    log "================================================================"
    log "Backup completed successfully!"
    log "Backup file: $BACKUP_PATH"
    log "================================================================"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -d|--dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -r|--retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        -s|--s3)
            S3_ENABLED="true"
            shift
            ;;
        -t|--test)
            log "Test mode - no actual backup will be performed"
            check_dependencies
            test_db_connection
            log "Test passed - environment is ready for backup"
            exit 0
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Run main function
main

exit 0