pipeline {
    agent any
    
    environment {
        // Docker configuration
        DOCKER_REGISTRY = credentials('docker-registry-credentials')
        IMAGE_NAME = "kuberbank/backend"
        IMAGE_TAG = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"
        
        // Database configuration for testing
        TEST_DB_HOST = "localhost"
        TEST_DB_PORT = "5432"
        TEST_DB_NAME = "kuberbank_test"
        TEST_DB_USER = "bankuser"
        TEST_DB_PASSWORD = credentials('test-db-password')
        
        // Notification
        SLACK_WEBHOOK = credentials('slack-webhook-url')
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo '========================================='
                echo '   Checking out source code...'
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
        
        stage('Install Dependencies') {
            steps {
                echo '========================================='
                echo '   Installing Node.js dependencies...'
                echo '========================================='
                dir('app/api') {
                    sh 'npm ci --production=false'
                }
            }
        }
        
        stage('Lint Code') {
            steps {
                echo '========================================='
                echo '   Running ESLint...'
                echo '========================================='
                dir('app/api') {
                    sh 'npm run lint || true'
                }
            }
        }
        
        stage('Unit Tests') {
            steps {
                echo '========================================='
                echo '   Running unit tests...'
                echo '========================================='
                dir('app/api') {
                    sh '''
                        npm test -- \
                            --coverage \
                            --coverageReporters=text \
                            --coverageReporters=lcov \
                            --testMatch='**/__tests__/**/*.test.js' \
                            --testPathIgnorePatterns='integration'
                    '''
                }
            }
            post {
                always {
                    // Publish test results
                    junit(
                        testResults: 'app/api/test-results/*.xml',
                        allowEmptyResults: true
                    )
                    
                    // Publish coverage report
                    publishHTML(
                        target: [
                            allowMissing: true,
                            alwaysLinkToLastBuild: true,
                            keepAll: true,
                            reportDir: 'app/api/coverage',
                            reportFiles: 'index.html',
                            reportName: 'Code Coverage'
                        ]
                    )
                }
            }
        }
        
        stage('Setup Test Database') {
            steps {
                echo '========================================='
                echo '   Setting up test database...           '
                echo '========================================='
                sh '''
                    # Check if PostgreSQL is running
                    if ! pg_isready -h ${TEST_DB_HOST} -p ${TEST_DB_PORT}; then
                        echo "PostgreSQL is not running!"
                        exit 1
                    fi
                    
                    # Drop and recreate test database
                    PGPASSWORD=${TEST_DB_PASSWORD} psql -h ${TEST_DB_HOST} -U ${TEST_DB_USER} -d postgres -c "DROP DATABASE IF EXISTS ${TEST_DB_NAME};"
                    PGPASSWORD=${TEST_DB_PASSWORD} psql -h ${TEST_DB_HOST} -U ${TEST_DB_USER} -d postgres -c "CREATE DATABASE ${TEST_DB_NAME};"
                    
                    # Run migrations - use absolute paths from workspace
                    echo "Running migrations from: ${WORKSPACE}/database/migrations/"
                    for file in ${WORKSPACE}/database/migrations/*.sql; do
                        if [ -f "$file" ]; then
                            echo "Running migration: $(basename "$file")"
                            PGPASSWORD=${TEST_DB_PASSWORD} psql -h ${TEST_DB_HOST} -U ${TEST_DB_USER} -d ${TEST_DB_NAME} -f "$file"
                        fi
                    done
                    
                    # Run functions - use absolute paths from workspace
                    echo "Running functions from: ${WORKSPACE}/database/functions/"
                    for file in ${WORKSPACE}/database/functions/*.sql; do
                        if [ -f "$file" ]; then
                            echo "Running functions: $(basename "$file")"
                            PGPASSWORD=${TEST_DB_PASSWORD} psql -h ${TEST_DB_HOST} -U ${TEST_DB_USER} -d ${TEST_DB_NAME} -f "$file"
                        fi
                    done
                    
                    echo "Test database ready!"
                '''
            }
        }
        
        stage('Integration Tests') {
            steps {
                echo '========================================='
                echo '   Running integration tests...'
                echo '========================================='
                dir('app/api') {
                    sh '''
                        export TEST_DB_HOST=${TEST_DB_HOST}
                        export TEST_DB_PORT=${TEST_DB_PORT}
                        export TEST_DB_NAME=${TEST_DB_NAME}
                        export TEST_DB_USER=${TEST_DB_USER}
                        export TEST_DB_PASSWORD=${TEST_DB_PASSWORD}
                        
                        npm test -- \
                            --testMatch='**/__tests__/**/integration.test.js' \
                            --runInBand
                    '''
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                echo '========================================='
                echo '   Building Docker image...'
                echo '========================================='
                sh """
                    cd app
                    docker build \
                        -t ${IMAGE_NAME}:${IMAGE_TAG} \
                        -t ${IMAGE_NAME}:latest \
                        --build-arg BUILD_DATE=\$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                        --build-arg VCS_REF=${env.GIT_COMMIT} \
                        --build-arg VERSION=${IMAGE_TAG} \
                        -f Dockerfile .
                    
                    echo "Docker image built successfully!"
                    docker images | grep ${IMAGE_NAME}
                """
            }
        }
        
        stage('Security Scan') {
            steps {
                echo '========================================='
                echo '   Running security scans...'
                echo '========================================='
                
                script {
                    // Check if Trivy is installed
                    def trivyInstalled = sh(
                        script: 'command -v trivy',
                        returnStatus: true
                    ) == 0
                    
                    if (trivyInstalled) {
                        sh """
                            echo "Running Trivy security scan..."
                            trivy image \
                                --severity HIGH,CRITICAL \
                                --format json \
                                --output trivy-report.json \
                                ${IMAGE_NAME}:${IMAGE_TAG} || true
                            
                            echo "Trivy scan completed"
                        """
                    } else {
                        echo "Trivy not installed, skipping container scan"
                    }
                }
                
                // NPM audit
                dir('app/api') {
                    sh 'npm audit --audit-level=moderate --production || true'
                }
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
        
        stage('Push Docker Image') {
            when {
                branch 'main'
            }
            steps {
                echo '========================================='
                echo '   Pushing Docker image to registry...'
                echo '========================================='
                script {
                    docker.withRegistry('https://registry.hub.docker.com', 'docker-registry-credentials') {
                        sh """
                            docker push ${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${IMAGE_NAME}:latest
                        """
                    }
                }
                echo "Image pushed: ${IMAGE_NAME}:${IMAGE_TAG}"
            }
        }
        
        // stage('Tag Release') {
        //     when {
        //         branch 'main'
        //     }
        //     steps {
        //         echo '========================================='
        //         echo '   Creating Git tag...'
        //         echo '========================================='
        //         script {
        //             def version = "v1.0.${env.BUILD_NUMBER}"
        //             sh """
        //                 git config user.name "Jenkins CI"
        //                 git config user.email "jenkins@kuberbank.io"
        //                 git tag -a ${version} -m "Release ${version} - Build #${env.BUILD_NUMBER}"
        //             """
        //             echo "Created tag: ${version}"
        //         }
        //     }
        // }
        
        // stage('Update Kubernetes Manifests') {
        //     when {
        //         branch 'main'
        //     }
        //     steps {
        //         echo '========================================='
        //         echo '   Updating Kubernetes manifests...'
        //         echo '========================================='
        //         sh """
        //             # Update image tag in deployment
        //             if [ -f k8s/backend/deployment.yaml ]; then
        //                 sed -i 's|image:.*kuberbank/backend.*|image: ${IMAGE_NAME}:${IMAGE_TAG}|g' k8s/backend/deployment.yaml
        //                 echo "Updated deployment.yaml with new image tag"
        //             fi
        //         """
        //     }
        // }
    }
    
    post {
        success {
            echo '========================================='
            echo '   ✓ Build Successful!'
            echo '========================================='
            script {
                def message = """
✅ *Build Successful*
*Project:* KuberBank Backend
*Branch:* ${env.BRANCH_NAME}
*Commit:* ${env.GIT_COMMIT?.take(7)}
*Author:* ${env.GIT_AUTHOR}
*Message:* ${env.GIT_COMMIT_MSG}
*Image:* ${IMAGE_NAME}:${IMAGE_TAG}
*Build:* #${env.BUILD_NUMBER}
*Duration:* ${currentBuild.durationString.replace(' and counting', '')}
                """.stripIndent()
                
                if (env.SLACK_WEBHOOK) {
                    sh """
                        curl -X POST ${SLACK_WEBHOOK} \
                            -H 'Content-Type: application/json' \
                            -d '{"text": "${message}"}' || true
                    """
                }
            }
        }
        
        failure {
            echo '========================================='
            echo '   ✗ Build Failed!'
            echo '========================================='
            script {
                def message = """
❌ *Build Failed*
*Project:* KuberBank Backend
*Branch:* ${env.BRANCH_NAME}
*Commit:* ${env.GIT_COMMIT?.take(7)}
*Author:* ${env.GIT_AUTHOR}
*Build:* #${env.BUILD_NUMBER}
*Stage:* ${env.STAGE_NAME}
                """.stripIndent()
                
                if (env.SLACK_WEBHOOK) {
                    sh """
                        curl -X POST ${SLACK_WEBHOOK} \
                            -H 'Content-Type: application/json' \
                            -d '{"text": "${message}"}' || true
                    """
                }
            }
        }
        
        always {
            echo '========================================='
            echo '   Cleaning up...'
            echo '========================================='
            
            // Clean up Docker images
            sh """
                docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true
                docker system prune -f || true
            """
            
            // Archive logs
            archiveArtifacts(
                artifacts: '**/*.log',
                allowEmptyArchive: true,
                fingerprint: true
            )
            
            cleanWs()
        }
    }
}