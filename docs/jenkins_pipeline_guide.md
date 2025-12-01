# 🚀 KuberBank Jenkins Pipeline Guide

Complete guide for Jenkins CI/CD pipeline - no docker-compose, everything runs in Jenkins.

## 📋 What This Pipeline Does

The Jenkins pipeline runs **all tests in Docker containers** directly in Jenkins:

```
1. Checkout code from Git
2. Create isolated Docker network
3. Start PostgreSQL in container
4. Run database migrations
5. Build test Docker image
6. Run linter in container
7. Run unit tests in container
8. Run integration tests (with database)
9. Build production Docker image
10. Test production image
11. Security scan
12. Push to Docker Hub (main branch)
13. Tag release
14. Update Kubernetes manifests
15. Cleanup all containers
```

## 🎯 Key Features

✅ **No Dependencies on Jenkins Host**: Everything runs in containers  
✅ **Isolated Environment**: Each build gets its own network  
✅ **Automatic Cleanup**: Resources cleaned up after every build  
✅ **Database Migration**: Runs from `database/` directory  
✅ **Multi-Stage Dockerfile**: Efficient image building  
✅ **Coverage Reports**: Published to Jenkins  
✅ **Slack Notifications**: Build status alerts  

## 🏗️ Pipeline Stages

### Stage 1: Checkout
- Clones repository
- Gets commit info and author

### Stage 2: Setup Test Environment
```bash
docker network create kuberbank-test-${BUILD_NUMBER}
```

### Stage 3: Start Test Database
```bash
docker run -d \
  --name test-postgres-${BUILD_NUMBER} \
  --network kuberbank-test-${BUILD_NUMBER} \
  postgres:15-alpine
```

### Stage 4: Initialize Database Schema
```bash
# Copy migrations from database/ directory
docker cp database/migrations test-postgres:/tmp/migrations

# Run each migration
docker exec test-postgres \
  psql -U bankuser -d kuberbank_test -f /tmp/migrations/001_init_schema.sql
```

### Stage 5: Build Test Image
```bash
docker build --target base -t kuberbank/backend:test .
```

### Stage 6: Code Quality - Linting
```bash
docker run --rm kuberbank/backend:test npm run lint
```

### Stage 7: Unit Tests
```bash
docker run --rm \
  --network kuberbank-test-${BUILD_NUMBER} \
  -v ${WORKSPACE}/coverage:/app/coverage \
  kuberbank/backend:test \
  npm run test:unit --coverage
```

### Stage 8: Integration Tests
```bash
docker run --rm \
  --network kuberbank-test-${BUILD_NUMBER} \
  -e TEST_DB_HOST=test-postgres \
  kuberbank/backend:test \
  npm run test:integration
```

### Stage 9: Build Production Image
```bash
docker build --target production -t kuberbank/backend:latest .
```

### Stage 10: Test Production Image
```bash
docker run -d kuberbank/backend:latest
# Test health endpoint
curl http://localhost:3000/health
```

### Stage 11: Security Scan
```bash
trivy image --severity HIGH,CRITICAL kuberbank/backend:latest
npm audit --production
```

### Stage 12: Push to Registry (main branch only)
```bash
docker push kuberbank/backend:abc1234
docker push kuberbank/backend:latest
```

### Stage 13: Tag Release (main branch only)
```bash
git tag -a v1.0.${BUILD_NUMBER}
```

### Stage 14: Update Manifests (main branch only)
```bash
sed -i 's|image:.*|image: kuberbank/backend:abc1234|' k8s/backend/deployment.yaml
```

### Stage 15: Cleanup (always runs)
```bash
docker stop test-postgres-${BUILD_NUMBER}
docker rm test-postgres-${BUILD_NUMBER}
docker network rm kuberbank-test-${BUILD_NUMBER}
```

## 📁 Required Files

```
KuberBank/
├── Jenkinsfile                 ← Main pipeline definition
├── app/
│   ├── Dockerfile              ← Multi-stage Docker build
│   ├── requirements.txt        ← System dependencies
│   └── api/
│       ├── package.json        ← Node dependencies
│       ├── jest.config.js      ← Test configuration
│       └── __tests__/          ← Test files
├── database/                   ← Database directory (not "db")
│   ├── migrations/             ← SQL migrations
│   │   └── 001_init_schema.sql
│   └── functions/              ← SQL functions
│       └── 001_banking_functions.sql
└── scripts/
    └── run-tests-jenkins.sh    ← Local testing script
```

## 🔧 Jenkins Setup

### Prerequisites

1. **Jenkins installed** (see JENKINS_SETUP.txt)
2. **Docker installed on Jenkins server**
   ```bash
   sudo apt install docker.io
   sudo usermod -aG docker jenkins
   sudo systemctl restart jenkins
   ```
3. **Jenkins user in docker group**
   ```bash
   sudo usermod -aG docker jenkins
   newgrp docker
   ```

### Required Jenkins Plugins

Install these in Jenkins → Manage Plugins:
- Pipeline
- Git
- Docker Pipeline
- Credentials Binding
- HTML Publisher
- JUnit
- Workspace Cleanup

### Jenkins Credentials

Configure in Jenkins → Credentials:

1. **docker-registry-credentials**
   - Type: Username with password
   - Username: Your Docker Hub username
   - Password: Your Docker Hub password/token

2. **test-db-password**
   - Type: Secret text
   - Secret: testpassword

3. **slack-webhook-url** (optional)
   - Type: Secret text
   - Secret: Your Slack webhook URL

### Create Pipeline Job

1. New Item → Pipeline
2. Name: "KuberBank-Pipeline"
3. Pipeline Definition: "Pipeline script from SCM"
4. SCM: Git
5. Repository URL: Your Git URL
6. Script Path: `Jenkinsfile`
7. Save

## 🧪 Testing Locally

Run the same pipeline locally before pushing:

```bash
# Make executable
chmod +x scripts/run-tests-jenkins.sh

# Run exactly what Jenkins does
./scripts/run-tests-jenkins.sh
```

This script mimics Jenkins exactly:
- Creates Docker network
- Starts PostgreSQL
- Runs migrations
- Builds test image
- Runs all tests
- Cleans up everything

## 📊 Viewing Results in Jenkins

After build completes:

### Test Results
1. Go to build page
2. Click "Test Result"
3. See pass/fail for each test

### Coverage Report
1. Go to build page
2. Click "Unit Test Coverage"
3. Browse HTML coverage report

### Console Output
1. Click on build number
2. Click "Console Output"
3. See full pipeline logs

## 🐛 Troubleshooting

### Problem: "Docker daemon not accessible"

```bash
# Add jenkins to docker group
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# Verify
sudo -u jenkins docker ps
```

### Problem: "Permission denied on /var/run/docker.sock"

```bash
sudo chmod 666 /var/run/docker.sock
# Or better:
sudo chown root:docker /var/run/docker.sock
```

### Problem: "Network already exists"

The pipeline uses unique network names per build: `kuberbank-test-${BUILD_NUMBER}`

If cleanup fails, manually remove:
```bash
docker network rm kuberbank-test-123
```

### Problem: "Database migration fails"

Check the path - it should be `database/migrations/` not `db/migrations/`

```bash
# Verify in Jenkinsfile
docker cp database/migrations ...
```

### Problem: "Tests fail in Jenkins but pass locally"

Run the test script locally first:
```bash
./scripts/run-tests-jenkins.sh
```

This runs exactly what Jenkins does.

## 📈 Pipeline Flow Diagram

```
┌─────────────┐
│  Git Push   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Jenkins   │
│  Triggered  │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────┐
│  Create Docker Network          │
│  (isolated for this build)      │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Start PostgreSQL Container     │
│  (test-postgres-BUILD_NUMBER)   │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Run Database Migrations        │
│  (from database/ directory)     │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Build Test Docker Image        │
│  (with all dependencies)        │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Run Linter in Container        │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Run Unit Tests in Container    │
│  (with coverage)                │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Run Integration Tests          │
│  (connected to test database)   │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Build Production Image         │
│  (multi-stage, optimized)       │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Test Production Image          │
│  (health check)                 │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Security Scan                  │
│  (Trivy + npm audit)            │
└──────┬──────────────────────────┘
       │
       ▼
    ┌──┴──┐
    │ If  │
    │main?│
    └──┬──┘
       │ Yes
       ▼
┌─────────────────────────────────┐
│  Push to Docker Hub             │
│  - kuberbank/backend:abc1234    │
│  - kuberbank/backend:latest     │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Tag Git Release                │
│  (v1.0.BUILD_NUMBER)            │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Update K8s Manifests           │
│  (new image tag)                │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│  Cleanup                        │
│  - Stop containers              │
│  - Remove network               │
│  - Prune images                 │
└──────┬──────────────────────────┘
       │
       ▼
┌─────────────┐
│   Done!     │
└─────────────┘
```

## ⚙️ Environment Variables

Jenkins sets these automatically:

```groovy
IMAGE_NAME = "kuberbank/backend"
IMAGE_TAG = "${GIT_COMMIT.take(7)}"
BUILD_NUMBER = "123"  // Jenkins build number
DOCKER_NETWORK = "kuberbank-test-${BUILD_NUMBER}"
TEST_DB_CONTAINER = "test-postgres-${BUILD_NUMBER}"
```

## 🔒 Security

### Container Security
- All tests run in isolated containers
- Unique network per build
- Non-root user in production image
- Security scanning with Trivy

### Credentials
- Never hardcode passwords
- Use Jenkins credentials
- Credentials injected as environment variables

### Image Security
- Multi-stage builds (minimal production image)
- Alpine base (smaller attack surface)
- Regular security scans

## 📝 What Gets Tested

### Unit Tests (30+ tests)
- API endpoints
- Account operations
- Transaction logic
- Input validation
- Error handling

### Integration Tests
- Database operations
- Real PostgreSQL connection
- Transaction workflows
- Concurrent operations

### Security
- Vulnerability scanning
- Dependency auditing
- Image scanning

## 🎯 Success Criteria

Build passes when:
- ✅ All unit tests pass
- ✅ All integration tests pass
- ✅ Code linting passes
- ✅ Production image builds
- ✅ Health check passes
- ✅ Security scan completes

Build fails when:
- ❌ Any test fails
- ❌ Docker build fails
- ❌ Database migration fails
- ❌ Health check fails

## 📮 Notifications

### Slack (if configured)

Success:
```
✅ Build Successful
Project: KuberBank Backend
Branch: main
Commit: abc1234
Image: kuberbank/backend:abc1234
Tests: All Passed ✓
```

Failure:
```
❌ Build Failed
Project: KuberBank Backend
Branch: main
Failed Stage: Integration Tests
Logs: https://jenkins/build/123/console
```

## 🚀 Quick Start

1. **Setup Jenkins** (follow JENKINS_SETUP.txt)
2. **Install Docker** on Jenkins server
3. **Configure credentials** in Jenkins
4. **Create pipeline job** pointing to Jenkinsfile
5. **Push to Git** - build triggers automatically!

## 💡 Tips

### Speed Up Builds
- Use Docker layer caching
- Minimize dependencies
- Parallel test execution

### Debug Failed Builds
1. Check Console Output
2. Look for red error messages
3. Run locally: `./scripts/run-tests-jenkins.sh`
4. Fix and push again

### Monitor Builds
- Set up Jenkins email notifications
- Use Slack integration
- Check build trends in Jenkins

---

**Everything runs in Docker - Jenkins only orchestrates!** 🐳

**Documentation:**
- JENKINS_SETUP.txt - Jenkins installation
- TESTING.md - Test details
- This file - Pipeline guide