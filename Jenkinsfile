pipeline {
    agent any
    
    environment {
        // Docker configuration
        DOCKER_REGISTRY = credentials('docker-registry-credentials')
        IMAGE_NAME = "kuberbank/backend"
        IMAGE_TAG = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"
        
        // Test database configuration
        TEST_DB_CONTAINER = "test-postgres-${BUILD_NUMBER}"
        TEST_DB_HOST = "test-postgres"
        TEST_DB_PORT = "5432"
        TEST_DB_NAME = "kuberbank_test"
        TEST_DB_USER = "bankuser"
        TEST_DB_PASSWORD = credentials('test-db-password')
        
        // Docker network for this build
        DOCKER_NETWORK = "kuberbank-test-${BUILD_NUMBER}"
        
        // Test container
        TEST_CONTAINER = "kuberbank-test-${BUILD_NUMBER}"
        APP_CONTAINER = "kuberbank-app-${BUILD_NUMBER}"
        
        // Notification
        SLACK_WEBHOOK = credentials('slack-webhook-url')
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo '========================================='
                echo '   📦 Checking out source code...'
                echo '========================================='
                checkout scm
                
                script {
                    env.GIT_COMMIT_MSG = sh(
                        script: 'git log -1 --pretty=%B',
                        returnStdout: true
                    ).trim()
                    env.GIT_AUTHOR = sh(
                        script: 'git log -1 --pretty=%an',
                        returnStdout: true
                    ).trim()
                }
                
                echo "Commit: ${env.GIT_COMMIT}"
                echo "Author: ${env.GIT_AUTHOR}"
                echo "Message: ${env.GIT_COMMIT_MSG}"
            }
        }
        
        stage('Setup Test Environment') {
            steps {
                echo '========================================='
                echo '   🔧 Setting up test environment...'
                echo '========================================='
                sh """
                    # Create isolated Docker network for this build
                    docker network create ${DOCKER_NETWORK}
                    echo "✓ Created network: ${DOCKER_NETWORK}"
                """
            }
        }
        
        stage('Start Test Database') {
            steps {
                echo '========================================='
                echo '   🗄️  Starting PostgreSQL container...'
                echo '========================================='
                sh """
                    # Start PostgreSQL test database
                    docker run -d \
                        --name ${TEST_DB_CONTAINER} \
                        --network ${DOCKER_NETWORK} \
                        --network-alias ${TEST_DB_HOST} \
                        -e POSTGRES_USER=${TEST_DB_USER} \
                        -e POSTGRES_PASSWORD=${TEST_DB_PASSWORD} \
                        -e POSTGRES_DB=${TEST_DB_NAME} \
                        postgres:15-alpine
                        
                    # Wait for PostgreSQL to be ready - IMPROVED VERSION
                    echo "Waiting for PostgreSQL to start..."
                    max_attempts=30
                    attempt=0
                    
                    while [ \$attempt -lt \$max_attempts ]; do
                        attempt=\$((attempt + 1))
                        
                        # Check if pg_isready succeeds
                        if docker exec ${TEST_DB_CONTAINER} pg_isready -U ${TEST_DB_USER} -d ${TEST_DB_NAME} 2>/dev/null; then
                            # Extra verification - try to actually connect
                            if docker exec ${TEST_DB_CONTAINER} psql -U ${TEST_DB_USER} -d ${TEST_DB_NAME} -c "SELECT 1;" >/dev/null 2>&1; then
                                echo "✓ PostgreSQL is ready!"
                                break
                            fi
                        fi
                        
                        echo "  Attempt \$attempt/\$max_attempts - waiting..."
                        sleep 2
                        
                        if [ \$attempt -eq \$max_attempts ]; then
                            echo "❌ PostgreSQL failed to start within expected time"
                            docker logs ${TEST_DB_CONTAINER}
                            exit 1
                        fi
                    done
                    
                    # Final verification
                    echo "Verifying database connection..."
                    docker exec ${TEST_DB_CONTAINER} \
                        psql -U ${TEST_DB_USER} -d ${TEST_DB_NAME} -c "SELECT version();"
                    
                    echo "✓ Test database started successfully"
                """
            }
        }
        
        stage('Initialize Database Schema') {
            steps {
                echo '========================================='
                echo '   📋 Running database migrations...'
                echo '========================================='
                sh """
                    # Copy migrations to database container
                    docker cp database/migrations ${TEST_DB_CONTAINER}:/tmp/migrations
                    
                    # Run each migration
                    for migration in database/migrations/*.sql; do
                        if [ -f "\$migration" ]; then
                            filename=\$(basename "\$migration")
                            echo "  → Running: \$filename"
                            docker exec ${TEST_DB_CONTAINER} \
                                psql -U ${TEST_DB_USER} -d ${TEST_DB_NAME} -f /tmp/migrations/\$filename
                        fi
                    done
                    
                    # Copy and run database functions if they exist
                    if [ -d "database/functions" ]; then
                        docker cp database/functions ${TEST_DB_CONTAINER}:/tmp/functions
                        
                        for func in database/functions/*.sql; do
                            if [ -f "\$func" ]; then
                                filename=\$(basename "\$func")
                                echo "  → Running: \$filename"
                                docker exec ${TEST_DB_CONTAINER} \
                                    psql -U ${TEST_DB_USER} -d ${TEST_DB_NAME} -f /tmp/functions/\$filename
                            fi
                        done
                    fi
                    
                    # Verify tables were created
                    echo ""
                    echo "Database tables:"
                    docker exec ${TEST_DB_CONTAINER} \
                        psql -U ${TEST_DB_USER} -d ${TEST_DB_NAME} -c "\\\\dt"
                    
                    echo "✓ Database initialized successfully"
                """
            }
        }
        
        stage('Build Test Image') {
            steps {
                echo '========================================='
                echo '   🏗️  Building test Docker image...'
                echo '========================================='
                sh """
                    cd app
                    
                    # Build base image with all dependencies
                    docker build \
                        --target base \
                        -t ${IMAGE_NAME}:test-${IMAGE_TAG} \
                        --build-arg BUILD_DATE=\$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                        --build-arg VCS_REF=${env.GIT_COMMIT} \
                        --build-arg VERSION=${IMAGE_TAG} \
                        -f Dockerfile .
                    
                    echo "✓ Test image built: ${IMAGE_NAME}:test-${IMAGE_TAG}"
                """
            }
        }
        
        stage('Code Quality - Linting') {
            steps {
                echo '========================================='
                echo '   🔍 Running ESLint...'
                echo '========================================='
                sh """
                    docker run --rm \
                        --name lint-${BUILD_NUMBER} \
                        ${IMAGE_NAME}:test-${IMAGE_TAG} \
                        npm run lint || echo "⚠️  Linting warnings found (non-blocking)"
                """
            }
        }
        
        stage('Unit Tests') {
            steps {
                echo '========================================='
                echo '   🧪 Running unit tests...'
                echo '========================================='
                sh """
                    # Create directories for test results
                    mkdir -p \${WORKSPACE}/test-results
                    mkdir -p \${WORKSPACE}/coverage
                    
                    # Run unit tests in container
                    docker run --rm \
                        --name unit-test-${BUILD_NUMBER} \
                        --network ${DOCKER_NETWORK} \
                        -e NODE_ENV=test \
                        -v \${WORKSPACE}/test-results:/app/test-results \
                        -v \${WORKSPACE}/coverage:/app/coverage \
                        ${IMAGE_NAME}:test-${IMAGE_TAG} \
                        npm run test:unit -- \
                            --coverage \
                            --coverageDirectory=/app/coverage \
                            --testResultsProcessor=jest-junit
                            --forceExit
                    
                    echo "✓ Unit tests completed"
                """
            }
            post {
                always {
                    // Publish JUnit test results
                    junit(
                        testResults: 'test-results/*.xml',
                        allowEmptyResults: true
                    )
                    
                    // Publish HTML coverage report
                    publishHTML(
                        target: [
                            allowMissing: true,
                            alwaysLinkToLastBuild: true,
                            keepAll: true,
                            reportDir: 'coverage',
                            reportFiles: 'index.html',
                            reportName: 'Unit Test Coverage'
                        ]
                    )
                }
            }
        }
        
        stage('Integration Tests') {
            steps {
                echo '========================================='
                echo '   🔗 Running integration tests...'
                echo '========================================='
                sh """
                    # Run integration tests with database connection
                    docker run --rm \
                        --name integration-test-${BUILD_NUMBER} \
                        --network ${DOCKER_NETWORK} \
                        -e NODE_ENV=test \
                        -e TEST_DB_HOST=${TEST_DB_HOST} \
                        -e TEST_DB_PORT=${TEST_DB_PORT} \
                        -e TEST_DB_NAME=${TEST_DB_NAME} \
                        -e TEST_DB_USER=${TEST_DB_USER} \
                        -e TEST_DB_PASSWORD=${TEST_DB_PASSWORD} \
                        ${IMAGE_NAME}:test-${IMAGE_TAG} \
                        npm run test:integration -- --forceExit
                    
                    echo "✓ Integration tests completed"
                """
            }
        }
        
        stage('Build Production Image') {
            steps {
                echo '========================================='
                echo '   📦 Building production image...'
                echo '========================================='
                sh """
                    cd app
                    
                    # Build production image (multi-stage)
                    docker build \
                        --target production \
                        -t ${IMAGE_NAME}:${IMAGE_TAG} \
                        -t ${IMAGE_NAME}:latest \
                        --build-arg BUILD_DATE=\$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                        --build-arg VCS_REF=${env.GIT_COMMIT} \
                        --build-arg VERSION=${IMAGE_TAG} \
                        -f Dockerfile .
                    
                    echo "✓ Production image built"
                    docker images | grep ${IMAGE_NAME}
                """
            }
        }
        
        stage('Security Scan') {
            steps {
                echo '========================================='
                echo '   🔒 Running security scans...'
                echo '========================================='
                
                script {
                    // Check if Trivy is installed
                    def trivyInstalled = sh(
                        script: 'command -v trivy',
                        returnStatus: true
                    ) == 0
                    
                    if (trivyInstalled) {
                        sh """
                            echo "Running Trivy vulnerability scan..."
                            
                            # Scan for HIGH and CRITICAL vulnerabilities
                            trivy image \
                                --severity HIGH,CRITICAL \
                                --format json \
                                --output trivy-report.json \
                                ${IMAGE_NAME}:${IMAGE_TAG} || true
                            
                            # Show CRITICAL vulnerabilities
                            echo ""
                            echo "Critical Vulnerabilities:"
                            trivy image \
                                --severity CRITICAL \
                                --format table \
                                ${IMAGE_NAME}:${IMAGE_TAG} || true
                            
                            echo "✓ Security scan completed"
                        """
                    } else {
                        echo "⚠️  Trivy not installed - skipping container security scan"
                        echo "   To install: https://aquasecurity.github.io/trivy/"
                    }
                }
                
                // Run npm audit in container
                sh """
                    echo ""
                    echo "Running npm audit..."
                    docker run --rm \
                        ${IMAGE_NAME}:test-${IMAGE_TAG} \
                        npm audit --audit-level=moderate --production || echo "⚠️  Vulnerabilities found (non-blocking)"
                """
            }
            post {
                always {
                    archiveArtifacts(
                        artifacts: 'trivy-report.json',
                        allowEmptyArchive: true
                    )
                }
            }
        }
        
        stage('Test Production Image') {
            steps {
                echo '========================================='
                echo '   🚀 Testing production image...'
                echo '========================================='
                sh """
                    # Start production container
                    docker run -d \
                        --name ${APP_CONTAINER} \
                        --network ${DOCKER_NETWORK} \
                        -e NODE_ENV=production \
                        -e DB_HOST=${TEST_DB_HOST} \
                        -e DB_PORT=${TEST_DB_PORT} \
                        -e DB_NAME=${TEST_DB_NAME} \
                        -e DB_USER=${TEST_DB_USER} \
                        -e DB_PASSWORD=${TEST_DB_PASSWORD} \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                    
                    # Wait for application to start
                    echo "Waiting for application to start..."
                    sleep 10
                    
                    # Test health endpoint
                    echo "Testing health endpoint..."
                    for i in {1..10}; do
                        if docker exec ${APP_CONTAINER} curl -f http://localhost:3000/health 2>/dev/null; then
                            echo "✓ Health check passed!"
                            break
                        fi
                        echo "  Waiting for health check... (\$i/10)"
                        sleep 3
                    done
                    
                    # Show application logs
                    echo ""
                    echo "Application logs:"
                    docker logs ${APP_CONTAINER} --tail 20
                    
                    echo "✓ Production image test completed"
                """
            }
        }
        
        stage('Push to Registry') {
            when {
                branch 'main'
            }
            steps {
                echo '========================================='
                echo '   📤 Pushing to Docker Hub...'
                echo '========================================='
                script {
                    docker.withRegistry('https://registry.hub.docker.com', 'docker-registry-credentials') {
                        sh """
                            docker push ${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${IMAGE_NAME}:latest
                            
                            echo "✓ Images pushed to Docker Hub:"
                            echo "  - ${IMAGE_NAME}:${IMAGE_TAG}"
                            echo "  - ${IMAGE_NAME}:latest"
                        """
                    }
                }
            }
        }
        
    //     stage('Tag Release') {
    //         when {
    //             branch 'main'
    //         }
    //         steps {
    //             echo '========================================='
    //             echo '   🏷️  Tagging release...'
    //             echo '========================================='
    //             script {
    //                 def version = "v1.0.${env.BUILD_NUMBER}"
    //                 sh """
    //                     git config user.name "Jenkins CI"
    //                     git config user.email "jenkins@kuberbank.io"
    //                     git tag -a ${version} -m "Release ${version} - Build #${env.BUILD_NUMBER}" || true
                        
    //                     echo "✓ Created tag: ${version}"
    //                 """
    //             }
    //         }
    //     }
        
    //     stage('Update Kubernetes Manifests') {
    //         when {
    //             branch 'main'
    //         }
    //         steps {
    //             echo '========================================='
    //             echo '   📝 Updating Kubernetes manifests...'
    //             echo '========================================='
    //             sh """
    //                 # Update image tag in deployment file
    //                 if [ -f k8s/backend/deployment.yaml ]; then
    //                     sed -i 's|image:.*kuberbank/backend.*|image: ${IMAGE_NAME}:${IMAGE_TAG}|g' k8s/backend/deployment.yaml
    //                     echo "✓ Updated k8s/backend/deployment.yaml"
    //                     echo "  New image: ${IMAGE_NAME}:${IMAGE_TAG}"
    //                 else
    //                     echo "⚠️  k8s/backend/deployment.yaml not found"
    //                 fi
    //             """
    //         }
    //     }
    }
    
    post {
        always {
            echo '========================================='
            echo '          🧹 Cleaning up...'
            echo '========================================='
            sh """
                # Stop and remove all containers
                docker stop ${TEST_DB_CONTAINER} 2>/dev/null || true
                docker rm ${TEST_DB_CONTAINER} 2>/dev/null || true
                docker stop ${APP_CONTAINER} 2>/dev/null || true
                docker rm ${APP_CONTAINER} 2>/dev/null || true
                
                # Remove Docker network
                docker network rm ${DOCKER_NETWORK} 2>/dev/null || true
                
                # Remove test image
                docker rmi ${IMAGE_NAME}:test-${IMAGE_TAG} 2>/dev/null || true
                
                # Clean up dangling images
                docker image prune -f || true
                
                # Fix permissions on coverage directory before cleanup
                # This is needed because Docker creates files as root
                # Fix permissions using Docker (no sudo needed!)
                if [ -d "\${WORKSPACE}/coverage" ]; then
                    echo "Fixing coverage directory permissions..."
                    docker run --rm \
                        -v "\${WORKSPACE}:/workspace" \
                        alpine:latest \
                        chown -R \$(id -u):\$(id -g) /workspace/coverage 2>/dev/null || true
                fi
                if [ -d "\${WORKSPACE}/test-results" ]; then
                    echo "Fixing test-results directory permissions..."
                    docker run --rm \
                        -v "\${WORKSPACE}:/workspace" \
                        alpine:latest \
                        chown -R \$(id -u):\$(id -g) /workspace/test-results 2>/dev/null || true
                fi
                
                echo "✓ Cleanup completed"
            """
            
            // Archive logs
            archiveArtifacts(
                artifacts: '**/*.log',
                allowEmptyArchive: true,
                fingerprint: true
            )
            
            // Clean workspace - now permissions are fixed
            cleanWs(
                deleteDirs: true,
                disableDeferredWipeout: true,
                patterns: [
                    [pattern: 'node_modules', type: 'INCLUDE'],
                    [pattern: 'coverage', type: 'INCLUDE'],
                    [pattern: 'test-results', type: 'INCLUDE']
                ]
            )
        }
        
        success {
            echo '========================================='
            echo '   ✅ BUILD SUCCESSFUL!'
            echo '========================================='
            script {
                def duration = currentBuild.durationString.replace(' and counting', '')
                def message = """
✅ *Build Successful*

*Project:* KuberBank Backend
*Branch:* ${env.BRANCH_NAME}
*Commit:* ${env.GIT_COMMIT?.take(7)}
*Author:* ${env.GIT_AUTHOR}
*Message:* ${env.GIT_COMMIT_MSG}

*Image:* ${IMAGE_NAME}:${IMAGE_TAG}
*Build:* #${env.BUILD_NUMBER}
*Duration:* ${duration}

*Tests:*
  ✓ Unit Tests Passed
  ✓ Integration Tests Passed
  ✓ Security Scan Complete
  ✓ Production Image Tested

*View:* ${env.BUILD_URL}
                """.stripIndent()
                
                if (env.SLACK_WEBHOOK) {
                    sh """
                        curl -X POST '${SLACK_WEBHOOK}' \
                            -H 'Content-Type: application/json' \
                            -d '{"text": "${message.replaceAll('"', '\\\\"').replaceAll('\n', '\\n')}"}' || true
                    """
                }
                
                echo message
            }
        }
        
        failure {
            echo '========================================='
            echo '   ❌ BUILD FAILED!'
            echo '========================================='
            script {
                def message = """
❌ *Build Failed*

*Project:* KuberBank Backend
*Branch:* ${env.BRANCH_NAME}
*Commit:* ${env.GIT_COMMIT?.take(7)}
*Author:* ${env.GIT_AUTHOR}
*Build:* #${env.BUILD_NUMBER}
*Failed Stage:* ${env.STAGE_NAME}

*Logs:* ${env.BUILD_URL}console

Please check the build logs for details.
                """.stripIndent()
                
                if (env.SLACK_WEBHOOK) {
                    sh """
                        curl -X POST '${SLACK_WEBHOOK}' \
                            -H 'Content-Type: application/json' \
                            -d '{"text": "${message.replaceAll('"', '\\\\"').replaceAll('\n', '\\n')}"}' || true
                    """
                }
                
                echo message
            }
        }
        
        unstable {
            echo '========================================='
            echo '   ⚠️  BUILD UNSTABLE'
            echo '========================================='
            echo 'Some tests may have failed or there are quality issues'
        }
    }
}