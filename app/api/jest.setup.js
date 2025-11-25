// ================================================================
// Jest Setup File
// Description: Setup and teardown for tests
// ================================================================

// Set test environment variables
process.env.NODE_ENV = 'test';
process.env.LOG_LEVEL = 'error'; // Reduce log noise during tests

// Set default test database configuration
if (!process.env.TEST_DB_HOST) {
  process.env.TEST_DB_HOST = 'localhost';
}
if (!process.env.TEST_DB_PORT) {
  process.env.TEST_DB_PORT = '5432';
}
if (!process.env.TEST_DB_NAME) {
  process.env.TEST_DB_NAME = 'kuberbank_test';
}
if (!process.env.TEST_DB_USER) {
  process.env.TEST_DB_USER = 'bankuser';
}

// Increase timeout for integration tests
jest.setTimeout(30000);

// Global test utilities
global.delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

global.generateRandomEmail = () => {
  return `test.${Date.now()}.${Math.random().toString(36).substring(7)}@test.com`;
};

global.generateAccountNumber = () => {
  return `KB${Date.now()}${Math.floor(Math.random() * 10000).toString().padStart(4, '0')}`;
};

// Console suppression for cleaner test output
const originalConsole = {
  log: console.log,
  error: console.error,
  warn: console.warn,
  info: console.info
};

beforeAll(() => {
  // Suppress console during tests unless DEBUG is set
  if (process.env.DEBUG !== 'true') {
    console.log = jest.fn();
    console.info = jest.fn();
    console.warn = jest.fn();
    // Keep errors visible
    // console.error = jest.fn();
  }
});

afterAll(() => {
  // Restore console
  console.log = originalConsole.log;
  console.error = originalConsole.error;
  console.warn = originalConsole.warn;
  console.info = originalConsole.info;
});

// Custom matchers
expect.extend({
  toBeValidAccountNumber(received) {
    const pass = /^KB\d{10,}$/.test(received);
    if (pass) {
      return {
        message: () => `expected ${received} not to be a valid account number`,
        pass: true,
      };
    } else {
      return {
        message: () => `expected ${received} to be a valid account number (format: KB followed by 10+ digits)`,
        pass: false,
      };
    }
  },
  
  toBeValidEmail(received) {
    const pass = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(received);
    if (pass) {
      return {
        message: () => `expected ${received} not to be a valid email`,
        pass: true,
      };
    } else {
      return {
        message: () => `expected ${received} to be a valid email`,
        pass: false,
      };
    }
  },
  
  toBePositiveNumber(received) {
    const pass = typeof received === 'number' && received > 0;
    if (pass) {
      return {
        message: () => `expected ${received} not to be a positive number`,
        pass: true,
      };
    } else {
      return {
        message: () => `expected ${received} to be a positive number`,
        pass: false,
      };
    }
  }
});

// Export test utilities
module.exports = {
  delay: global.delay,
  generateRandomEmail: global.generateRandomEmail,
  generateAccountNumber: global.generateAccountNumber
};