// ================================================================
// KuberBank API Unit Tests
// Description: Unit tests for API endpoints
// ================================================================

const request = require('supertest');
const { Pool } = require('pg');

// Mock the database pool
jest.mock('pg', () => {
  const mPool = {
    connect: jest.fn(),
    query: jest.fn(),
    end: jest.fn(),
  };
  return { Pool: jest.fn(() => mPool) };
});

describe('KuberBank API Tests', () => {
  let app;
  let pool;

  beforeAll(() => {
    // Set test environment
    process.env.NODE_ENV = 'test';
    process.env.DB_HOST = 'localhost';
    process.env.DB_PORT = '5432';
    process.env.DB_NAME = 'kuberbank_test';
    process.env.DB_USER = 'bankuser';
    process.env.DB_PASSWORD = 'testpassword';

    // Import app after setting environment
    app = require('../server');
    pool = new Pool();
  });

  afterAll(async () => {
    await pool.end();
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Health Check Endpoints', () => {
    test('GET /health - should return healthy status', async () => {
      pool.query.mockResolvedValueOnce({ rows: [{ result: 1 }] });

      const response = await request(app)
        .get('/health')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('status', 'healthy');
      expect(response.body).toHaveProperty('database', 'connected');
    });

    test('GET /health - should return unhealthy when DB fails', async () => {
      pool.query.mockRejectedValueOnce(new Error('Database connection failed'));

      const response = await request(app)
        .get('/health')
        .expect(503);

      expect(response.body).toHaveProperty('status', 'unhealthy');
      expect(response.body).toHaveProperty('database', 'disconnected');
    });

    test('GET /ready - should return ready status', async () => {
      pool.query.mockResolvedValueOnce({ rows: [{ result: 1 }] });

      const response = await request(app)
        .get('/ready')
        .expect(200);

      expect(response.body).toHaveProperty('status', 'ready');
    });

    test('GET /metrics - should return prometheus metrics', async () => {
      const response = await request(app)
        .get('/metrics')
        .expect(200);

      expect(response.text).toContain('http_request_duration_seconds');
    });
  });

  describe('Account Endpoints', () => {
    const mockClient = {
      query: jest.fn(),
      release: jest.fn(),
    };

    beforeEach(() => {
      pool.connect.mockResolvedValue(mockClient);
    });

    test('POST /api/accounts - should create new account', async () => {
      const accountData = {
        firstName: 'John',
        lastName: 'Doe',
        email: 'john.doe@test.com',
        initialDeposit: 1000
      };

      mockClient.query
        .mockResolvedValueOnce({ rows: [] }) // BEGIN
        .mockResolvedValueOnce({ rows: [{ id: 1 }] }) // INSERT user
        .mockResolvedValueOnce({ rows: [{ id: 1, account_number: 'KB2025010100001' }] }) // INSERT account
        .mockResolvedValueOnce({ rows: [] }) // INSERT transaction
        .mockResolvedValueOnce({ rows: [] }); // COMMIT

      const response = await request(app)
        .post('/api/accounts')
        .send(accountData)
        .expect('Content-Type', /json/)
        .expect(201);

      expect(response.body).toHaveProperty('success', true);
      expect(response.body.data).toHaveProperty('accountNumber');
      expect(response.body.data).toHaveProperty('balance', 1000);
      expect(mockClient.release).toHaveBeenCalled();
    });

    test('POST /api/accounts - should fail with invalid email', async () => {
      const accountData = {
        firstName: 'John',
        lastName: 'Doe',
        email: 'invalid-email',
        initialDeposit: 1000
      };

      const response = await request(app)
        .post('/api/accounts')
        .send(accountData)
        .expect(400);

      expect(response.body).toHaveProperty('success', false);
    });

    test('GET /api/accounts/:accountNumber - should return account details', async () => {
      const mockAccount = {
        id: 1,
        account_number: 'KB2025010100001',
        balance: 5000.00,
        status: 'active',
        first_name: 'John',
        last_name: 'Doe',
        email: 'john.doe@test.com'
      };

      pool.query.mockResolvedValueOnce({ rows: [mockAccount] });

      const response = await request(app)
        .get('/api/accounts/KB2025010100001')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('success', true);
      expect(response.body.data).toHaveProperty('account_number', 'KB2025010100001');
      expect(response.body.data).toHaveProperty('balance', 5000.00);
    });

    test('GET /api/accounts/:accountNumber - should return 404 for non-existent account', async () => {
      pool.query.mockResolvedValueOnce({ rows: [] });

      const response = await request(app)
        .get('/api/accounts/KB9999999999')
        .expect(404);

      expect(response.body).toHaveProperty('success', false);
      expect(response.body).toHaveProperty('error', 'Account not found');
    });
  });

  describe('Transaction Endpoints', () => {
    const mockClient = {
      query: jest.fn(),
      release: jest.fn(),
    };

    beforeEach(() => {
      pool.connect.mockResolvedValue(mockClient);
    });

    test('POST /api/transactions - should process deposit', async () => {
      const transactionData = {
        accountNumber: 'KB2025010100001',
        type: 'deposit',
        amount: 500,
        description: 'Test deposit'
      };

      mockClient.query
        .mockResolvedValueOnce({ rows: [] }) // BEGIN
        .mockResolvedValueOnce({ rows: [{ id: 1, balance: 5000 }] }) // SELECT account
        .mockResolvedValueOnce({ rows: [] }) // UPDATE balance
        .mockResolvedValueOnce({ rows: [{ id: 1, created_at: new Date() }] }) // INSERT transaction
        .mockResolvedValueOnce({ rows: [] }); // COMMIT

      const response = await request(app)
        .post('/api/transactions')
        .send(transactionData)
        .expect('Content-Type', /json/)
        .expect(201);

      expect(response.body).toHaveProperty('success', true);
      expect(response.body.data).toHaveProperty('newBalance', 5500);
    });

    test('POST /api/transactions - should process withdrawal', async () => {
      const transactionData = {
        accountNumber: 'KB2025010100001',
        type: 'withdrawal',
        amount: 500,
        description: 'Test withdrawal'
      };

      mockClient.query
        .mockResolvedValueOnce({ rows: [] }) // BEGIN
        .mockResolvedValueOnce({ rows: [{ id: 1, balance: 5000 }] }) // SELECT account
        .mockResolvedValueOnce({ rows: [] }) // UPDATE balance
        .mockResolvedValueOnce({ rows: [{ id: 1, created_at: new Date() }] }) // INSERT transaction
        .mockResolvedValueOnce({ rows: [] }); // COMMIT

      const response = await request(app)
        .post('/api/transactions')
        .send(transactionData)
        .expect(201);

      expect(response.body).toHaveProperty('success', true);
      expect(response.body.data).toHaveProperty('newBalance', 4500);
    });

    test('POST /api/transactions - should fail with insufficient funds', async () => {
      const transactionData = {
        accountNumber: 'KB2025010100001',
        type: 'withdrawal',
        amount: 10000,
        description: 'Test withdrawal'
      };

      mockClient.query
        .mockResolvedValueOnce({ rows: [] }) // BEGIN
        .mockResolvedValueOnce({ rows: [{ id: 1, balance: 5000 }] }) // SELECT account
        .mockRejectedValueOnce(new Error('Insufficient funds')); // Should fail

      const response = await request(app)
        .post('/api/transactions')
        .send(transactionData)
        .expect(400);

      expect(response.body).toHaveProperty('success', false);
      expect(response.body).toHaveProperty('error');
    });

    test('GET /api/accounts/:accountNumber/transactions - should return transaction history', async () => {
      const mockTransactions = [
        {
          id: 1,
          type: 'deposit',
          amount: 1000,
          description: 'Initial deposit',
          status: 'completed',
          created_at: new Date()
        },
        {
          id: 2,
          type: 'withdrawal',
          amount: 200,
          description: 'ATM withdrawal',
          status: 'completed',
          created_at: new Date()
        }
      ];

      pool.query.mockResolvedValueOnce({ rows: mockTransactions });

      const response = await request(app)
        .get('/api/accounts/KB2025010100001/transactions')
        .expect(200);

      expect(response.body).toHaveProperty('success', true);
      expect(response.body.data).toHaveLength(2);
      expect(response.body.data[0]).toHaveProperty('type', 'deposit');
    });
  });

  describe('Transfer Endpoints', () => {
    const mockClient = {
      query: jest.fn(),
      release: jest.fn(),
    };

    beforeEach(() => {
      pool.connect.mockResolvedValue(mockClient);
    });

    test('POST /api/transfers - should transfer funds between accounts', async () => {
      const transferData = {
        fromAccount: 'KB2025010100001',
        toAccount: 'KB2025010200001',
        amount: 250,
        description: 'Test transfer'
      };

      mockClient.query
        .mockResolvedValueOnce({ rows: [] }) // BEGIN
        .mockResolvedValueOnce({ rows: [
          { id: 1, account_number: 'KB2025010100001', balance: 5000 },
          { id: 2, account_number: 'KB2025010200001', balance: 3000 }
        ] }) // SELECT both accounts
        .mockResolvedValueOnce({ rows: [] }) // UPDATE from account
        .mockResolvedValueOnce({ rows: [] }) // UPDATE to account
        .mockResolvedValueOnce({ rows: [] }) // INSERT from transaction
        .mockResolvedValueOnce({ rows: [] }) // INSERT to transaction
        .mockResolvedValueOnce({ rows: [] }); // COMMIT

      const response = await request(app)
        .post('/api/transfers')
        .send(transferData)
        .expect(201);

      expect(response.body).toHaveProperty('success', true);
      expect(response.body).toHaveProperty('message', 'Transfer completed');
    });

    test('POST /api/transfers - should fail with non-existent account', async () => {
      const transferData = {
        fromAccount: 'KB2025010100001',
        toAccount: 'KB9999999999',
        amount: 250,
        description: 'Test transfer'
      };

      mockClient.query
        .mockResolvedValueOnce({ rows: [] }) // BEGIN
        .mockResolvedValueOnce({ rows: [
          { id: 1, account_number: 'KB2025010100001', balance: 5000 }
        ] }) // SELECT only one account
        .mockRejectedValueOnce(new Error('Account not found'));

      const response = await request(app)
        .post('/api/transfers')
        .send(transferData)
        .expect(404);

      expect(response.body).toHaveProperty('success', false);
    });
  });

  describe('Input Validation', () => {
    test('Should reject negative amounts', async () => {
      const response = await request(app)
        .post('/api/transactions')
        .send({
          accountNumber: 'KB2025010100001',
          type: 'deposit',
          amount: -100,
          description: 'Invalid amount'
        })
        .expect(400);

      expect(response.body).toHaveProperty('success', false);
    });

    test('Should reject invalid transaction type', async () => {
      const response = await request(app)
        .post('/api/transactions')
        .send({
          accountNumber: 'KB2025010100001',
          type: 'invalid_type',
          amount: 100,
          description: 'Invalid type'
        })
        .expect(400);

      expect(response.body).toHaveProperty('success', false);
    });

    test('Should reject invalid account number format', async () => {
      const response = await request(app)
        .get('/api/accounts/INVALID123')
        .expect(400);

      expect(response.body).toHaveProperty('success', false);
    });
  });

  describe('Rate Limiting', () => {
    test('Should rate limit excessive requests', async () => {
      const requests = [];
      
      // Make 110 requests (limit is 100 per 15 minutes)
      for (let i = 0; i < 110; i++) {
        requests.push(
          request(app)
            .get('/api/accounts/KB2025010100001')
        );
      }

      const responses = await Promise.all(requests);
      const rateLimited = responses.filter(r => r.status === 429);

      expect(rateLimited.length).toBeGreaterThan(0);
    });
  });

  describe('Error Handling', () => {
    test('Should handle database connection errors gracefully', async () => {
      pool.connect.mockRejectedValueOnce(new Error('Connection timeout'));

      const response = await request(app)
        .get('/api/accounts/KB2025010100001')
        .expect(500);

      expect(response.body).toHaveProperty('success', false);
      expect(response.body).toHaveProperty('error');
    });

    test('Should handle malformed JSON', async () => {
      const response = await request(app)
        .post('/api/accounts')
        .set('Content-Type', 'application/json')
        .send('{"invalid json}')
        .expect(400);

      expect(response.body).toHaveProperty('success', false);
    });
  });
});