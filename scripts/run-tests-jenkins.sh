#!/bin/bash
# ================================================================
# KuberBank Jenkins-Style Test Runner
# Description: Mimics exactly what Jenkins does - no docker-compose
# Usage: ./run-tests-jenkins.sh
# ================================================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration (mimics Jenkins environment)
BUILD_NUMBER=${BUILD_NUMBER:-$(date +%s)}
NETWORK_NAME="kuberbank-test-${BUILD_NUMBER}"
DB_CONTAINER="test-postgres-${BUILD_NUMBER}"
TEST_CONTAINER="kuberbank-test-${BUILD_NUMBER}"
APP_CONTAINER="kuberbank-app-${BUILD_NUMBER}"
IMAGE_NAME="kuberbank/backend"
IMAGE_TAG="test-${BUILD_NUMBER}"
DB_HOST="test-postgres"
DB_USER="bankuser"
DB_PASSWORD="testpassword"
DB_NAME="kuberbank_test"

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1" >&2
}

info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

cleanup() {
    log "🧹 Cleaning up Docker resources..."
    
    docker stop $DB_CONTAINER 2>/dev/null || true
    docker rm $DB_CONTAINER 2>/dev/null || true
    docker stop $APP_CONTAINER 2>/dev/null || true
    docker rm $APP_CONTAINER 2>/dev/null || true
    docker network rm $NETWORK_NAME 2>/dev/null || true
    docker rmi ${IMAGE_NAME}:${IMAGE_TAG} 2>/dev/null || true
    docker image prune -f >/dev/null 2>&1 || true
    
    log "✓ Cleanup completed"
}

trap cleanup EXIT

print_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   KuberBank Jenkins-Style Test Runner                     ║
║   Running tests exactly as Jenkins does                   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
}

check_docker() {
    if ! docker info >/dev/null 2>&1; then
        error "Docker is not running"
        error "Please start Docker and try again"
        exit 1
    fi
}

check_project_root() {
    if [ ! -f "Jenkinsfile" ] || [ ! -d "app" ]; then
        error "This script must be run from the project root directory"
        exit 1
    fi
}

main() {
    print_banner
    
    log "========================================="
    log "Stage 1: Setup Test Environment"
    log "========================================="
    
    docker network create $NETWORK_NAME
    info "✓ Created network: $NETWORK_NAME"
    
    log ""
    log "========================================="
    log "Stage 2: Start Test Database"
    log "========================================="
    
    docker run -d \
        --name $DB_CONTAINER \
        --network $NETWORK_NAME \
        --network-alias $DB_HOST \
        -e POSTGRES_USER=$DB_USER \
        -e POSTGRES_PASSWORD=$DB_PASSWORD \
        -e POSTGRES_DB=$DB_NAME \
        postgres:15-alpine
    
    info "Waiting for PostgreSQL to be ready..."
    for i in {1..30}; do
        if docker exec $DB_CONTAINER pg_isready -U $DB_USER -d $DB_NAME >/dev/null 2>&1; then
            info "✓ PostgreSQL is ready!"
            break
        fi
        printf "."
        sleep 2
    done
    echo ""
    
    log ""
    log "========================================="
    log "Stage 3: Initialize Database Schema"
    log "========================================="
    
    # Copy and run migrations
    docker cp database/migrations $DB_CONTAINER:/tmp/migrations
    
    for migration in database/migrations/*.sql; do
        if [ -f "$migration" ]; then
            filename=$(basename "$migration")
            info "  → Running: $filename"
            docker exec $DB_CONTAINER \
                psql -U $DB_USER -d $DB_NAME -f /tmp/migrations/$filename >/dev/null
        fi
    done
    
    # Copy and run functions
    if [ -d "database/functions" ]; then
        docker cp database/functions $DB_CONTAINER:/tmp/functions
        for func in database/functions/*.sql; do
            if [ -f "$func" ]; then
                filename=$(basename "$func")
                info "  → Running: $filename"
                docker exec $DB_CONTAINER \
                    psql -U $DB_USER -d $DB_NAME -f /tmp/functions/$filename >/dev/null
            fi
        done
    fi
    
    info "✓ Database initialized"
    
    log ""
    log "========================================="
    log "Stage 4: Build Test Image"
    log "========================================="
    
    cd app
    docker build \
        --target base \
        -t ${IMAGE_NAME}:${IMAGE_TAG} \
        -q \
        -f Dockerfile . >/dev/null
    cd ..
    
    info "✓ Test image built: ${IMAGE_NAME}:${IMAGE_TAG}"
    
    log ""
    log "========================================="
    log "Stage 5: Code Quality - Linting"
    log "========================================="
    
    docker run --rm \
        ${IMAGE_NAME}:${IMAGE_TAG} \
        npm run lint || echo "⚠️  Linting warnings (non-blocking)"
    
    log ""
    log "========================================="
    log "Stage 6: Unit Tests"
    log "========================================="
    
    mkdir -p test-results coverage
    
    docker run --rm \
        --network $NETWORK_NAME \
        -e NODE_ENV=test \
        -v "$(pwd)/test-results:/app/test-results" \
        -v "$(pwd)/coverage:/app/coverage" \
        ${IMAGE_NAME}:${IMAGE_TAG} \
        npm run test:unit -- \
            --coverage \
            --coverageDirectory=/app/coverage \
            --testResultsProcessor=jest-junit
    
    info "✓ Unit tests passed"
    
    log ""
    log "========================================="
    log "Stage 7: Integration Tests"
    log "========================================="
    
    docker run --rm \
        --network $NETWORK_NAME \
        -e NODE_ENV=test \
        -e TEST_DB_HOST=$DB_HOST \
        -e TEST_DB_PORT=5432 \
        -e TEST_DB_NAME=$DB_NAME \
        -e TEST_DB_USER=$DB_USER \
        -e TEST_DB_PASSWORD=$DB_PASSWORD \
        ${IMAGE_NAME}:${IMAGE_TAG} \
        npm run test:integration
    
    info "✓ Integration tests passed"
    
    log ""
    log "========================================="
    log "Stage 8: Build Production Image"
    log "========================================="
    
    cd app
    docker build \
        --target production \
        -t ${IMAGE_NAME}:latest \
        -q \
        -f Dockerfile . >/dev/null
    cd ..
    
    info "✓ Production image built"
    
    log ""
    log "========================================="
    log "Stage 9: Test Production Image"
    log "========================================="
    
    docker run -d \
        --name $APP_CONTAINER \
        --network $NETWORK_NAME \
        -e NODE_ENV=production \
        -e DB_HOST=$DB_HOST \
        -e DB_PORT=5432 \
        -e DB_NAME=$DB_NAME \
        -e DB_USER=$DB_USER \
        -e DB_PASSWORD=$DB_PASSWORD \
        ${IMAGE_NAME}:latest
    
    info "Waiting for application to start..."
    sleep 10
    
    for i in {1..10}; do
        if docker exec $APP_CONTAINER curl -f http://localhost:3000/health >/dev/null 2>&1; then
            info "✓ Health check passed!"
            break
        fi
        printf "."
        sleep 2
    done
    echo ""
    
    log ""
    log "========================================="
    log "Stage 10: Security Scan"
    log "========================================="
    
    if command -v trivy >/dev/null 2>&1; then
        trivy image --severity CRITICAL ${IMAGE_NAME}:latest || echo "⚠️  Vulnerabilities found"
    else
        echo "⚠️  Trivy not installed - skipping security scan"
    fi
    
    docker run --rm ${IMAGE_NAME}:${IMAGE_TAG} \
        npm audit --audit-level=moderate --production || echo "⚠️  NPM vulnerabilities found"
    
    log ""
    log "════════════════════════════════════════"
    log "✅ ALL TESTS PASSED!"
    log "════════════════════════════════════════"
    echo ""
    info "Test Results:"
    if [ -f "test-results/junit.xml" ]; then
        info "  - JUnit: test-results/junit.xml"
    fi
    if [ -f "coverage/index.html" ]; then
        info "  - Coverage: coverage/index.html"
        
        # Try to open coverage report
        if command -v xdg-open >/dev/null 2>&1; then
            xdg-open coverage/index.html 2>/dev/null &
        elif command -v open >/dev/null 2>&1; then
            open coverage/index.html 2>/dev/null &
        fi
    fi
    log "════════════════════════════════════════"
}

# Pre-flight checks
check_docker
check_project_root

# Run main
main

exit 0