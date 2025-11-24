#!/bin/bash
# ================================================================
# KuberBank Database Initialization Script
# Description: Initialize database with schema, functions, and seed data
# Usage: ./init_db.sh [options]
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
DB_ADMIN_USER="${DB_ADMIN_USER:-postgres}"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-}"

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MIGRATIONS_DIR="${PROJECT_ROOT}/migrations"
FUNCTIONS_DIR="${PROJECT_ROOT}/functions"
SEEDS_DIR="${PROJECT_ROOT}/seeds"

# Options
SKIP_CREATE_DB="false"
SKIP_SEEDS="false"
FORCE_INIT="false"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

usage() {
    cat << EOF
KuberBank Database Initialization Script

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -f, --force             Force initialization (drop existing database)
    --skip-create           Skip database creation (use existing)
    --skip-seeds            Skip seed data insertion
    --test                  Test mode (check prerequisites only)

Environment Variables:
    DB_HOST                 Database host (default: localhost)
    DB_PORT                 Database port (default: 5432)
    DB_NAME                 Database name (default: kuberbank)
    DB_USER                 Database user (default: bankuser)
    DB_PASSWORD             Database password
    DB_ADMIN_USER           Admin user (default: postgres)
    DB_ADMIN_PASSWORD       Admin password

Examples:
    $0                      # Initialize with all defaults
    $0 --force              # Force reinitialization
    $0 --skip-seeds         # Initialize without seed data
    $0 --test               # Test prerequisites only

EOF
    exit 0
}

print_banner() {
    cat << 'EOF'
================================================================
   _  __      _               ____              _    
  | |/ /_   _| |__   ___ _ _| __ )  __ _ _ __ | | __
  | ' /| | | | '_ \ / _ \ '__|  _ \ / _` | '_ \| |/ /
  | . \| |_| | |_) |  __/ |  | |_) | (_| | | | |   < 
  |_|\_\\__,_|_.__/ \___|_|  |____/ \__,_|_| |_|_|\_\
                                                      
  Database Initialization
================================================================
EOF
}

check_dependencies() {
    log "Checking dependencies..."
    
    local missing_deps=()
    
    command -v psql >/dev/null 2>&1 || missing_deps+=("psql")
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing dependencies: ${missing_deps[*]}"
        error "Please install PostgreSQL client tools"
        exit 1
    fi
    
    log "All dependencies satisfied"
}

test_connection() {
    log "Testing database server connection..."
    
    export PGPASSWORD="$DB_ADMIN_PASSWORD"
    
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d postgres -c "SELECT version();" >/dev/null 2>&1; then
        local version=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d postgres -t -c "SELECT version();" 2>/dev/null | head -n1 | xargs)
        log "Connection successful"
        info "PostgreSQL version: $version"
    else
        error "Failed to connect to PostgreSQL server"
        error "Host: $DB_HOST, Port: $DB_PORT, User: $DB_ADMIN_USER"
        exit 1
    fi
}

check_database_exists() {
    export PGPASSWORD="$DB_ADMIN_PASSWORD"
    
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
        return 0
    else
        return 1
    fi
}

create_user() {
    log "Creating database user..."
    
    export PGPASSWORD="$DB_ADMIN_PASSWORD"
    
    # Check if user exists
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
        info "User $DB_USER already exists"
    else
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d postgres -c "
            CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
        " >/dev/null
        log "User $DB_USER created"
    fi
}

create_database() {
    if [ "$SKIP_CREATE_DB" = "true" ]; then
        log "Skipping database creation"
        return 0
    fi
    
    if check_database_exists; then
        if [ "$FORCE_INIT" = "true" ]; then
            warning "Database exists. Dropping and recreating..."
            
            export PGPASSWORD="$DB_ADMIN_PASSWORD"
            
            # Terminate connections
            psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d postgres -c "
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();
            " >/dev/null 2>&1
            
            # Drop database
            psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d postgres -c "DROP DATABASE $DB_NAME;" >/dev/null
            log "Database dropped"
        else
            info "Database $DB_NAME already exists (use --force to recreate)"
            return 0
        fi
    fi
    
    log "Creating database $DB_NAME..."
    
    export PGPASSWORD="$DB_ADMIN_PASSWORD"
    
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d postgres -c "
        CREATE DATABASE $DB_NAME
        WITH OWNER = $DB_USER
        ENCODING = 'UTF8'
        LC_COLLATE = 'en_US.UTF-8'
        LC_CTYPE = 'en_US.UTF-8'
        TEMPLATE = template0;
    " >/dev/null
    
    # Grant privileges
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_ADMIN_USER" -d postgres -c "
        GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
    " >/dev/null
    
    log "Database $DB_NAME created successfully"
}

run_migrations() {
    log "Running database migrations..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if [ ! -d "$MIGRATIONS_DIR" ]; then
        error "Migrations directory not found: $MIGRATIONS_DIR"
        exit 1
    fi
    
    local migration_count=0
    for migration_file in "$MIGRATIONS_DIR"/*.sql; do
        if [ -f "$migration_file" ]; then
            local filename=$(basename "$migration_file")
            info "Running migration: $filename"
            
            if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$migration_file" >/dev/null 2>&1; then
                info "✓ $filename completed"
                ((migration_count++))
            else
                error "✗ $filename failed"
                exit 1
            fi
        fi
    done
    
    log "Completed $migration_count migrations"
}

run_functions() {
    log "Creating database functions..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if [ ! -d "$FUNCTIONS_DIR" ]; then
        warning "Functions directory not found: $FUNCTIONS_DIR"
        return 0
    fi
    
    local function_count=0
    for function_file in "$FUNCTIONS_DIR"/*.sql; do
        if [ -f "$function_file" ]; then
            local filename=$(basename "$function_file")
            info "Running: $filename"
            
            if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$function_file" >/dev/null 2>&1; then
                info "✓ $filename completed"
                ((function_count++))
            else
                error "✗ $filename failed"
                exit 1
            fi
        fi
    done
    
    log "Created $function_count function files"
}

run_seeds() {
    if [ "$SKIP_SEEDS" = "true" ]; then
        log "Skipping seed data"
        return 0
    fi
    
    log "Loading seed data..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if [ ! -d "$SEEDS_DIR" ]; then
        warning "Seeds directory not found: $SEEDS_DIR"
        return 0
    fi
    
    local seed_count=0
    for seed_file in "$SEEDS_DIR"/*.sql; do
        if [ -f "$seed_file" ]; then
            local filename=$(basename "$seed_file")
            info "Running seed: $filename"
            
            if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$seed_file" >/dev/null 2>&1; then
                info "✓ $filename completed"
                ((seed_count++))
            else
                error "✗ $filename failed"
                exit 1
            fi
        fi
    done
    
    log "Loaded $seed_count seed files"
}

verify_installation() {
    log "Verifying database installation..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    # Check tables
    local table_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | xargs)
    
    info "Tables created: $table_count"
    
    # Check functions
    local function_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -t -c "SELECT COUNT(*) FROM pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');" | xargs)
    
    info "Functions created: $function_count"
    
    # Check data
    if [ "$SKIP_SEEDS" != "true" ]; then
        local user_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -t -c "SELECT COUNT(*) FROM users;" | xargs)
        local account_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -t -c "SELECT COUNT(*) FROM accounts;" | xargs)
        
        info "Sample users: $user_count"
        info "Sample accounts: $account_count"
    fi
    
    log "Database verification successful"
}

print_summary() {
    cat << EOF

================================================================
Database Initialization Summary
================================================================

Database:        $DB_NAME
Host:            $DB_HOST:$DB_PORT
User:            $DB_USER

Status:          ✓ Successfully initialized

Next Steps:
  1. Test the API connection
  2. Access the frontend at http://localhost:8080
  3. Use sample accounts:
     - john.doe@example.com (KB2025010100001)
     - jane.smith@example.com (KB2025010200001)

Useful Commands:
  psql -h $DB_HOST -U $DB_USER -d $DB_NAME
  ./backup.sh
  ./restore.sh <backup_file>

================================================================
EOF
}

# ================================================================
# MAIN SCRIPT
# ================================================================

main() {
    print_banner
    
    log "Starting database initialization..."
    log "Target: $DB_NAME@$DB_HOST:$DB_PORT"
    
    # Check dependencies
    check_dependencies
    
    # Test connection
    test_connection
    
    # Create user
    create_user
    
    # Create database
    create_database
    
    # Run migrations
    run_migrations
    
    # Run functions
    run_functions
    
    # Load seed data
    run_seeds
    
    # Verify installation
    verify_installation
    
    # Print summary
    print_summary
}

# ================================================================
# PARSE ARGUMENTS
# ================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -f|--force)
            FORCE_INIT="true"
            shift
            ;;
        --skip-create)
            SKIP_CREATE_DB="true"
            shift
            ;;
        --skip-seeds)
            SKIP_SEEDS="true"
            shift
            ;;
        --test)
            check_dependencies
            test_connection
            log "Test passed - ready for initialization"
            exit 0
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