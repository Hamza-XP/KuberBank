#!/bin/bash
# ================================================================
# KuberBank Test Runner Script
# Description: Run all tests with proper setup
# Usage: ./run-tests.sh [unit|integration|all]
# ================================================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
TEST_TYPE="${1:-all}"
DB_HOST="${TEST_DB_HOST:-localhost}"
DB_PORT="${TEST_DB_PORT:-5432}"
DB_NAME="${TEST_DB_NAME:-kuberbank_test}"
DB_USER="${TEST_DB_USER:-bankuser}"
DB_PASSWORD="${TEST_DB_PASSWORD:-testpassword}"

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING:${NC} $1"
}

print_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   KuberBank Test Runner                                   ║
║   Running automated tests...                              ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
}

check_dependencies() {
    log "Checking dependencies..."
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed"
        exit 1
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        error "npm is not installed"
        exit 1
    fi
    
    # Check PostgreSQL client
    if ! command -v psql &> /dev/null; then
        warning "psql not found - integration tests may fail"
    fi
    
    log "Dependencies check passed"
}

check_database() {
    log "Checking database connection..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT 1" &> /dev/null; then
        error "Cannot connect to PostgreSQL at $DB_HOST:$DB_PORT"
        error "Please ensure PostgreSQL is running and credentials are correct"
        exit 1
    fi
    
    log "Database connection successful"
}

setup_test_database() {
    log "Setting up test database..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    # Drop existing test database
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
        -c "DROP DATABASE IF EXISTS $DB_NAME;" &> /dev/null || true
    
    # Create test database
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
        -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" &> /dev/null
    
    log "Test database created: $DB_NAME"
    
    # Run migrations
    log "Running migrations..."
    for migration in database/migrations/*.sql; do
        if [ -f "$migration" ]; then
            log "  → $(basename "$migration")"
            psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
                -f "$migration" &> /dev/null
        fi
    done
    
    # Run functions
    if [ -d "database/functions" ]; then
        log "Loading database functions..."
        for func in database/functions/*.sql; do
            if [ -f "$func" ]; then
                log "  → $(basename "$func")"
                psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
                    -f "$func" &> /dev/null
            fi
        done
    fi
    
    log "Test database setup complete"
}

install_dependencies() {
    log "Installing Node.js dependencies..."
    
    cd app/api
    npm ci --silent
    cd ../..
    
    log "Dependencies installed"
}

run_unit_tests() {
    log "Running unit tests..."
    
    cd app/api
    npm run test:unit
    local exit_code=$?
    cd ../..
    
    if [ $exit_code -eq 0 ]; then
        log "✓ Unit tests passed"
    else
        error "✗ Unit tests failed"
        exit $exit_code
    fi
}

run_integration_tests() {
    log "Running integration tests..."
    
    # Set test database environment
    export TEST_DB_HOST="$DB_HOST"
    export TEST_DB_PORT="$DB_PORT"
    export TEST_DB_NAME="$DB_NAME"
    export TEST_DB_USER="$DB_USER"
    export TEST_DB_PASSWORD="$DB_PASSWORD"
    
    cd app/api
    npm run test:integration
    local exit_code=$?
    cd ../..
    
    if [ $exit_code -eq 0 ]; then
        log "✓ Integration tests passed"
    else
        error "✗ Integration tests failed"
        exit $exit_code
    fi
}

run_all_tests() {
    log "Running all tests..."
    
    # Set test database environment
    export TEST_DB_HOST="$DB_HOST"
    export TEST_DB_PORT="$DB_PORT"
    export TEST_DB_NAME="$DB_NAME"
    export TEST_DB_USER="$DB_USER"
    export TEST_DB_PASSWORD="$DB_PASSWORD"
    
    cd app/api
    npm test -- --coverage
    local exit_code=$?
    cd ../..
    
    if [ $exit_code -eq 0 ]; then
        log "✓ All tests passed"
    else
        error "✗ Some tests failed"
        exit $exit_code
    fi
}

cleanup() {
    log "Cleaning up..."
    
    # Optionally drop test database
    if [ "$CLEANUP_DB" = "true" ]; then
        export PGPASSWORD="$DB_PASSWORD"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
            -c "DROP DATABASE IF EXISTS $DB_NAME;" &> /dev/null || true
        log "Test database cleaned up"
    fi
}

print_summary() {
    echo ""
    log "════════════════════════════════════════════"
    log "Test Summary"
    log "════════════════════════════════════════════"
    log "Test Type: $TEST_TYPE"
    log "Database: $DB_NAME@$DB_HOST:$DB_PORT"
    
    if [ -f "app/api/coverage/coverage-summary.json" ]; then
        log "Coverage report: app/api/coverage/index.html"
    fi
    
    log "════════════════════════════════════════════"
}

# Main execution
main() {
    print_banner
    
    # Check dependencies
    check_dependencies
    
    # Install Node.js dependencies
    install_dependencies
    
    case "$TEST_TYPE" in
        unit)
            log "Running unit tests only..."
            run_unit_tests
            ;;
        integration)
            log "Running integration tests only..."
            check_database
            setup_test_database
            run_integration_tests
            ;;
        all)
            log "Running all tests..."
            check_database
            setup_test_database
            run_all_tests
            ;;
        *)
            error "Invalid test type: $TEST_TYPE"
            echo "Usage: $0 [unit|integration|all]"
            exit 1
            ;;
    esac
    
    # Print summary
    print_summary
    
    log "✓ Tests completed successfully!"
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main
main

exit 0