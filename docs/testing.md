# 🧪 KuberBank Testing Guide

Complete guide for running and understanding KuberBank tests.

## 📋 Table of Contents

- [Overview](#overview)
- [Test Structure](#test-structure)
- [Prerequisites](#prerequisites)
- [Running Tests](#running-tests)
- [Test Coverage](#test-coverage)
- [CI/CD Integration](#cicd-integration)
- [Writing Tests](#writing-tests)
- [Troubleshooting](#troubleshooting)

## 🎯 Overview

KuberBank includes comprehensive testing:
- **Unit Tests**: Test individual functions and API endpoints
- **Integration Tests**: Test with real database
- **Coverage Reporting**: Track code coverage
- **CI/CD Integration**: Automated testing in Jenkins

## 📁 Test Structure

```
app/api/
├── __tests__/
│   ├── api.test.js           # Unit tests
│   └── integration.test.js   # Integration tests
├── jest.config.js            # Jest configuration
├── jest.setup.js             # Test setup and utilities
├── .eslintrc.js              # Linting rules
└── package.json              # Test scripts

scripts/
└── run-tests.sh              # Test runner script
```

## ✅ Prerequisites

### Required Software

```bash
# Node.js 18+
node --version

# npm 9+
npm --version

# PostgreSQL 15+
psql --version

# Docker (for building images)
docker --version
```

### Database Setup

```bash
# Start PostgreSQL
sudo systemctl start postgresql

# Create test database and user
sudo -u postgres psql
CREATE USER bankuser WITH PASSWORD 'testpassword';
CREATE DATABASE kuberbank_test OWNER bankuser;
GRANT ALL PRIVILEGES ON DATABASE kuberbank_test TO bankuser;
\q
```

### Environment Variables

Create `.env.test` in `app/api/`:

```bash
NODE_ENV=test
TEST_DB_HOST=localhost
TEST_DB_PORT=5432
TEST_DB_NAME=kuberbank_test
TEST_DB_USER=bankuser
TEST_DB_PASSWORD=testpassword
```

## 🚀 Running Tests

### Quick Start

```bash
# Install dependencies
cd app/api
npm install

# Run all tests
npm test

# Run with coverage
npm run test:coverage
```

### Using Test Runner Script

```bash
# Make script executable
chmod +x scripts/run-tests.sh

# Run all tests
./scripts/run-tests.sh all

# Run only unit tests
./scripts/run-tests.sh unit

# Run only integration tests
./scripts/run-tests.sh integration
```

### Individual Test Commands

```bash
cd app/api

# Unit tests only
npm run test:unit

# Integration tests only
npm run test:integration

# Watch mode (for development)
npm run test:watch

# CI mode
npm run test:ci
```

## 📊 Test Coverage

### Viewing Coverage

```bash
# Generate coverage report
npm run test:coverage

# Open HTML report
open coverage/index.html
# or
xdg-open coverage/index.html  # Linux
```

### Coverage Thresholds

Current thresholds (in `jest.config.js`):
- **Branches**: 50%
- **Functions**: 50%
- **Lines**: 50%
- **Statements**: 50%

### Coverage Reports

Generated reports:
- `coverage/index.html` - HTML report (browse)
- `coverage/lcov.info` - LCOV format (for CI tools)
- `coverage/coverage-summary.json` - JSON summary

## 🔄 CI/CD Integration

### Jenkins Pipeline

The Jenkinsfile includes automated testing:

```groovy
stage('Unit Tests') {
    steps {
        sh 'npm test -- --coverage'
    }
}

stage('Integration Tests') {
    steps {
        sh 'npm run test:integration'
    }
}
```

### Test Results in Jenkins

After build:
1. Go to build page
2. Click "Test Result" to see test reports
3. Click "Coverage Report" for coverage

### Failed Tests

Jenkins will:
- ❌ Mark build as failed
- 📧 Send notifications (if configured)
- 📊 Show which tests failed
- 📝 Display error messages

## ✍️ Writing Tests

### Unit Test Example

```javascript
// __tests__/myFeature.test.js
describe('My Feature', () => {
  test('should do something', () => {
    const result = myFunction(input);
    expect(result).toBe(expected);
  });
});
```

### Integration Test Example

```javascript
// __tests__/integration.test.js
describe('API Integration', () => {
  test('should create account', async () => {
    const response = await request(app)
      .post('/api/accounts')
      .send(accountData)
      .expect(201);
    
    expect(response.body.success).toBe(true);
  });
});
```

### Custom Matchers

Available custom matchers:

```javascript
// Check if valid account number
expect('KB2025010100001').toBeValidAccountNumber();

// Check if valid email
expect('test@example.com').toBeValidEmail();

// Check if positive number
expect(100).toBePositiveNumber();
```

### Test Utilities

Available in `jest.setup.js`:

```javascript
// Wait for async operations
await delay(1000);

// Generate random email
const email = generateRandomEmail();

// Generate account number
const accountNum = generateAccountNumber();
```

## 🐛 Troubleshooting

### Tests Failing to Connect to Database

**Problem**: `Error: connect ECONNREFUSED`

**Solution**:
```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql

# Start PostgreSQL
sudo systemctl start postgresql

# Verify connection
psql -h localhost -U bankuser -d kuberbank_test -c "SELECT 1"
```

### Database Permission Errors

**Problem**: `permission denied for database`

**Solution**:
```bash
sudo -u postgres psql
GRANT ALL PRIVILEGES ON DATABASE kuberbank_test TO bankuser;
ALTER USER bankuser CREATEDB;
\q
```

### Port Already in Use

**Problem**: `Port 5432 is already in use`

**Solution**:
```bash
# Find process using port
sudo lsof -i :5432

# Or use different port
export TEST_DB_PORT=5433
```

### Tests Timeout

**Problem**: `Timeout - Async callback was not invoked`

**Solution**:
```javascript
// Increase timeout in test
test('long running test', async () => {
  // test code
}, 60000); // 60 second timeout

// Or globally in jest.config.js
testTimeout: 60000
```

### Module Not Found

**Problem**: `Cannot find module 'somepackage'`

**Solution**:
```bash
# Clear npm cache
npm cache clean --force

# Delete node_modules and reinstall
rm -rf node_modules package-lock.json
npm install
```

### Coverage Not Generating

**Problem**: Coverage reports not created

**Solution**:
```bash
# Install jest explicitly
npm install --save-dev jest

# Run with explicit coverage flag
npm test -- --coverage --verbose
```

### Integration Tests Fail but Unit Tests Pass

**Problem**: Integration tests fail, unit tests pass

**Solution**:
```bash
# Ensure test database is set up
./scripts/run-tests.sh integration

# Check migrations were run
psql -h localhost -U bankuser -d kuberbank_test -c "\dt"

# Reset test database
dropdb -U bankuser kuberbank_test
createdb -U bankuser kuberbank_test
psql -U bankuser -d kuberbank_test -f database/migrations/001_init_schema.sql
```

## 📈 Best Practices

### 1. Test Organization

```
✓ Group related tests with describe()
✓ Use descriptive test names
✓ One assertion per test when possible
✓ Use beforeEach/afterEach for setup/cleanup
```

### 2. Database Testing

```
✓ Always clean up test data
✓ Use transactions when possible
✓ Don't depend on specific data IDs
✓ Test with realistic data
```

### 3. Async Testing

```
✓ Always use async/await with promises
✓ Handle rejections properly
✓ Set appropriate timeouts
✓ Use try/catch for error testing
```

### 4. Mocking

```
✓ Mock external services
✓ Don't mock what you're testing
✓ Clear mocks between tests
✓ Use realistic mock data
```

## 📊 Test Metrics

### Current Coverage

Run to see current coverage:
```bash
npm run test:coverage
```

### Test Performance

View test duration:
```bash
npm test -- --verbose
```

### Test Quality Metrics

- **Total Tests**: Check package.json scripts
- **Passing Rate**: Should be 100%
- **Coverage**: Aim for >80%
- **Duration**: Should be <30 seconds

## 🔗 Related Documentation

- [Jest Documentation](https://jestjs.io/docs/getting-started)
- [Supertest Documentation](https://github.com/visionmedia/supertest)
- [PostgreSQL Testing Best Practices](https://wiki.postgresql.org/wiki/Testing)

## 💡 Tips

### Speed Up Tests

```bash
# Run tests in parallel
npm test -- --maxWorkers=4

# Run only changed tests
npm test -- --onlyChanged

# Run specific test file
npm test -- api.test.js
```

### Debug Tests

```bash
# Run with verbose output
npm test -- --verbose

# Run in watch mode
npm run test:watch

# Use Node debugger
node --inspect-brk node_modules/.bin/jest --runInBand
```

### Generate Test Data

```javascript
// Use factory functions
const createTestAccount = () => ({
  firstName: 'Test',
  lastName: 'User',
  email: generateRandomEmail(),
  initialDeposit: 1000
});
```

## 🎯 Goals

- ✅ Maintain >80% code coverage
- ✅ All tests pass before merging
- ✅ Integration tests with real database
- ✅ Fast test execution (<30s)
- ✅ Clear test documentation

---

**Need Help?**
- Open an issue: https://github.com/Hamza-XP/KuberBank/issues
- Check logs in `test-results/`
- Review test output carefully

**Happy Testing!** 🧪