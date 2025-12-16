// ================================================================
// KuberBank API Integration Tests
// Description: Integration tests with real database
// ================================================================

const request = require('supertest');
const { Pool } = require('pg');

describe('KuberBank API Integration Tests', () => {
  let app;
  let pool;
  let testAccountNumber;

  beforeAll(async () => {
    // Set test environment
    process.env.NODE_ENV = 'test';
    // Use TEST_DB_HOST from environment (set by Jenkins to 'test-postgres')
    process.env.DB_HOST = process.env.TEST_DB_HOST || 'localhost';
    process.env.DB_PORT = process.env.TEST_DB_PORT || '5432';
    process.env.DB_NAME = process.env.TEST_DB_NAME || 'kuberbank_test';
    process.env.DB_USER = process.env.TEST_DB_USER || 'bankuser';
    process.env.DB_PASSWORD = process.env.TEST_DB_PASSWORD || 'testpassword';

    // Create database connection
    pool = new Pool({
      host: process.env.DB_HOST,
      port: process.env.DB_PORT,
      database: process.env.DB_NAME,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
    });

    // Wait for database to be ready with longer timeout
    let retries = 15; // Increased from 5
    let connected = false;
    
    while (retries > 0) {
      try {
        await pool.query('SELECT 1');
        console.log('✓ Database connection established');
        connected = true;
        break;
      } catch (error) {
        retries--;
        if (retries === 0) {
          console.error('Failed to connect to database:', error.message);
          throw new Error(`Database connection failed after 30 seconds. Host: ${process.env.DB_HOST}:${process.env.DB_PORT}`);
        }
        console.log(`Waiting for database... (${retries} retries left)`);
        await new Promise(resolve => setTimeout(resolve, 2000));
      }
    }

    // Import app after database is ready
    app = require('../server');
  }, 35000); // Increase timeout to 35 seconds.

  afterAll(async () => {
    // Cleanup test data
    if (testAccountNumber) {
      await pool.query(`
        DELETE FROM audit_logs
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number = $1
        )
      `, [testAccountNumber]);
        
      await pool.query(`
        DELETE FROM transactions
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number = $1
        )
      `, [testAccountNumber]);
        
      await pool.query(
        'DELETE FROM accounts WHERE account_number = $1',
        [testAccountNumber]
      );
    }
    await pool.end();
  });

  describe('End-to-End Account Flow', () => {
    let userId;
    let accountId;

    test('Step 1: Create a new account', async () => {
      const response = await request(app)
        .post('/api/accounts')
        .send({
          firstName: 'Integration',
          lastName: 'Test',
          email: `test.${Date.now()}@integration.test`,
          initialDeposit: 1000
        })
        .expect(201);

      expect(response.body.success).toBe(true);
      expect(response.body.data).toHaveProperty('accountNumber');
      expect(response.body.data.balance).toBe(1000);

      testAccountNumber = response.body.data.accountNumber;
      
      // Verify in database
      const dbResult = await pool.query(
        'SELECT * FROM accounts WHERE account_number = $1',
        [testAccountNumber]
      );
      
      expect(dbResult.rows).toHaveLength(1);
      expect(dbResult.rows[0].balance).toBe('1000.00');
      
      accountId = dbResult.rows[0].id;
      userId = dbResult.rows[0].user_id;
    });

    test('Step 2: Check account balance', async () => {
      const response = await request(app)
        .get(`/api/accounts/${testAccountNumber}`)
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.data.account_number).toBe(testAccountNumber);
      expect(parseFloat(response.body.data.balance)).toBe(1000);
    });

    test('Step 3: Make a deposit', async () => {
      const response = await request(app)
        .post('/api/transactions')
        .send({
          accountNumber: testAccountNumber,
          type: 'deposit',
          amount: 500,
          description: 'Integration test deposit'
        })
        .expect(201);

      expect(response.body.success).toBe(true);
      expect(response.body.data.newBalance).toBe(1500);

      // Verify in database
      const dbResult = await pool.query(
        'SELECT balance FROM accounts WHERE account_number = $1',
        [testAccountNumber]
      );
      
      expect(parseFloat(dbResult.rows[0].balance)).toBe(1500);
    });

    test('Step 4: Make a withdrawal', async () => {
      const response = await request(app)
        .post('/api/transactions')
        .send({
          accountNumber: testAccountNumber,
          type: 'withdrawal',
          amount: 300,
          description: 'Integration test withdrawal'
        })
        .expect(201);

      expect(response.body.success).toBe(true);
      expect(response.body.data.newBalance).toBe(1200);

      // Verify in database
      const dbResult = await pool.query(
        'SELECT balance FROM accounts WHERE account_number = $1',
        [testAccountNumber]
      );
      
      expect(parseFloat(dbResult.rows[0].balance)).toBe(1200);
    });

    test('Step 5: Check transaction history', async () => {
      const response = await request(app)
        .get(`/api/accounts/${testAccountNumber}/transactions`)
        .expect(200);

      expect(response.body.success).toBe(true);
      expect(response.body.data.length).toBeGreaterThanOrEqual(3); // initial + deposit + withdrawal

      const transactions = response.body.data;
      const deposit = transactions.find(t => t.type === 'deposit' && Number(t.amount) === 500);
      const withdrawal = transactions.find(t => t.type === 'withdrawal' && Number(t.amount) === 300);

      expect(deposit).toBeDefined();
      expect(withdrawal).toBeDefined();
    });

    test('Step 6: Verify audit log', async () => {
      const auditResult = await pool.query(
        'SELECT * FROM audit_logs WHERE account_id = $1 ORDER BY created_at DESC',
        [accountId]
      );

      expect(auditResult.rows.length).toBeGreaterThan(0);
      
      const balanceChanges = auditResult.rows.filter(
        log => log.action === 'balance_change'
      );
      
      expect(balanceChanges.length).toBeGreaterThan(0);
    });
  });

  describe('Transfer Flow', () => {
    let account1, account2;

    beforeAll(async () => {
      // Create two test accounts
      const response1 = await request(app)
        .post('/api/accounts')
        .send({
          firstName: 'Transfer',
          lastName: 'Test1',
          email: `transfer1.${Date.now()}@test.com`,
          initialDeposit: 5000
        });
      
      const response2 = await request(app)
        .post('/api/accounts')
        .send({
          firstName: 'Transfer',
          lastName: 'Test2',
          email: `transfer2.${Date.now()}@test.com`,
          initialDeposit: 1000
        });

      account1 = response1.body.data.accountNumber;
      account2 = response2.body.data.accountNumber;
    });

    test('Should transfer funds between accounts', async () => {
      const response = await request(app)
        .post('/api/transfers')
        .send({
          fromAccount: account1,
          toAccount: account2,
          amount: 750,
          description: 'Integration test transfer'
        })
        .expect(201);

      expect(response.body.success).toBe(true);

      // Check balances
      const balance1 = await request(app).get(`/api/accounts/${account1}`);
      const balance2 = await request(app).get(`/api/accounts/${account2}`);

      expect(parseFloat(balance1.body.data.balance)).toBe(4250);
      expect(parseFloat(balance2.body.data.balance)).toBe(1750);

      // Check transactions
      const txHistory1 = await request(app).get(`/api/accounts/${account1}/transactions`);
      const txHistory2 = await request(app).get(`/api/accounts/${account2}/transactions`);

      const withdrawal = txHistory1.body.data.find(
        t => t.type === 'withdrawal' && Number(t.amount) === 750
      );
      const deposit = txHistory2.body.data.find(
        t => t.type === 'deposit' && Number(t.amount) === 750
      );

      expect(withdrawal).toBeDefined();
      expect(deposit).toBeDefined();
      expect(withdrawal.description).toContain(account2);
      expect(deposit.description).toContain(account1);
    });

    afterAll(async () => {
      // Cleanup
      await pool.query(`
        DELETE FROM audit_logs
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number IN ($1, $2)
        )
      `, [account1, account2]);
      
      await pool.query(`
        DELETE FROM transactions
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number IN ($1, $2)
        )
      `, [account1, account2]);
      
      await pool.query(
        'DELETE FROM accounts WHERE account_number IN ($1, $2)',
        [account1, account2]
      );
    });
  });

  describe('Concurrent Transaction Handling', () => {
    let accountNumber;

    beforeAll(async () => {
      const response = await request(app)
        .post('/api/accounts')
        .send({
          firstName: 'Concurrent',
          lastName: 'Test',
          email: `concurrent.${Date.now()}@test.com`,
          initialDeposit: 10000
        });

      accountNumber = response.body.data.accountNumber;
    });

    test('Should handle concurrent deposits correctly', async () => {
      const deposits = Array(5).fill(null).map(() =>
        request(app)
          .post('/api/transactions')
          .send({
            accountNumber,
            type: 'deposit',
            amount: 100,
            description: 'Concurrent deposit'
          })
      );

      const responses = await Promise.all(deposits);
      
      // All should succeed
      responses.forEach(response => {
        expect(response.body.success).toBe(true);
      });

      // Final balance should be correct
      const finalBalance = await request(app).get(`/api/accounts/${accountNumber}`);
      expect(parseFloat(finalBalance.body.data.balance)).toBe(10500);
    });

    afterAll(async () => {
      await pool.query(`
        DELETE FROM audit_logs
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number = $1
        )
      `, [accountNumber]);
      
      await pool.query(`
        DELETE FROM transactions
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number = $1
        )
      `, [accountNumber]);
      
      await pool.query(
        'DELETE FROM accounts WHERE account_number = $1',
        [accountNumber]
      );
    });
  });

  describe('Error Scenarios', () => {
    test('Should prevent overdraft', async () => {
      const response = await request(app)
        .post('/api/accounts')
        .send({
          firstName: 'Overdraft',
          lastName: 'Test',
          email: `overdraft.${Date.now()}@test.com`,
          initialDeposit: 100
        });

      const accountNumber = response.body.data.accountNumber;

      const withdrawalResponse = await request(app)
        .post('/api/transactions')
        .send({
          accountNumber,
          type: 'withdrawal',
          amount: 200,
          description: 'Overdraft attempt'
        })
        .expect(400);

      expect(withdrawalResponse.body.success).toBe(false);
      expect(withdrawalResponse.body.error).toContain('Insufficient funds');

      // Cleanup
      await pool.query(`
        DELETE FROM audit_logs
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number = $1
        )
      `, [accountNumber]);
      await pool.query(`
        DELETE FROM transactions
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number = $1
        )
      `, [accountNumber]);
      await pool.query(
        'DELETE FROM accounts WHERE account_number = $1',
        [accountNumber]
      );
    });

    test('Should prevent transfer to same account', async () => {
      const response = await request(app)
        .post('/api/accounts')
        .send({
          firstName: 'Same',
          lastName: 'Account',
          email: `same.${Date.now()}@test.com`,
          initialDeposit: 1000
        });

      const accountNumber = response.body.data.accountNumber;

      const transferResponse = await request(app)
        .post('/api/transfers')
        .send({
          fromAccount: accountNumber,
          toAccount: accountNumber,
          amount: 100,
          description: 'Self transfer'
        })
        .expect(400);

      expect(transferResponse.body.success).toBe(false);

      // Cleanup
      await pool.query(`
        DELETE FROM audit_logs
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number = $1
        )
      `, [accountNumber]);
      await pool.query(`
        DELETE FROM transactions
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number = $1
        )
      `, [accountNumber]);
      await pool.query(
        'DELETE FROM accounts WHERE account_number = $1',
        [accountNumber]
      );
    });
  });

  describe('Database Triggers and Constraints', () => {
    test('Should update updated_at timestamp automatically', async () => {
      const response = await request(app)
        .post('/api/accounts')
        .send({
          firstName: 'Timestamp',
          lastName: 'Test',
          email: `timestamp.${Date.now()}@test.com`,
          initialDeposit: 1000
        });

      const accountNumber = response.body.data.accountNumber;

      // Get initial timestamp
      const result1 = await pool.query(
        'SELECT updated_at FROM accounts WHERE account_number = $1',
        [accountNumber]
      );
      const timestamp1 = result1.rows[0].updated_at;

      // Wait a moment
      await new Promise(resolve => setTimeout(resolve, 1000));

      // Make a transaction
      await request(app)
        .post('/api/transactions')
        .send({
          accountNumber,
          type: 'deposit',
          amount: 100,
          description: 'Timestamp test'
        });

      // Check updated timestamp
      const result2 = await pool.query(
        'SELECT updated_at FROM accounts WHERE account_number = $1',
        [accountNumber]
      );
      const timestamp2 = result2.rows[0].updated_at;

      expect(new Date(timestamp2) > new Date(timestamp1)).toBe(true);

      // Cleanup
      await pool.query(`
        DELETE FROM audit_logs
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number = $1
        )
      `, [accountNumber]);
      await pool.query(`
        DELETE FROM transactions
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number = $1
        )
      `, [accountNumber]);
      await pool.query(
        'DELETE FROM accounts WHERE account_number = $1',
        [accountNumber]
      );
    });

    test('Should create audit log on balance change', async () => {
      const response = await request(app)
        .post('/api/accounts')
        .send({
          firstName: 'Audit',
          lastName: 'Test',
          email: `audit.${Date.now()}@test.com`,
          initialDeposit: 1000
        });

      const accountNumber = response.body.data.accountNumber;

      // Get account ID
      const accountResult = await pool.query(
        'SELECT id FROM accounts WHERE account_number = $1',
        [accountNumber]
      );
      const accountId = accountResult.rows[0].id;

      // Make a deposit
      await request(app)
        .post('/api/transactions')
        .send({
          accountNumber,
          type: 'deposit',
          amount: 500,
          description: 'Audit test'
        });

      // Check audit log
      const auditResult = await pool.query(
        'SELECT * FROM audit_logs WHERE account_id = $1 AND action = $2',
        [accountId, 'balance_change']
      );

      expect(auditResult.rows.length).toBeGreaterThan(0);
      
      const latestLog = auditResult.rows[auditResult.rows.length - 1];
      expect(latestLog.old_values).toHaveProperty('balance');
      expect(latestLog.new_values).toHaveProperty('balance');

      // Cleanup
      await pool.query(`
        DELETE FROM audit_logs
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number = $1
        )
      `, [accountNumber]);
      await pool.query(`
        DELETE FROM transactions
        WHERE account_id IN (
          SELECT id FROM accounts WHERE account_number = $1
        )
      `, [accountNumber]);
      await pool.query(
        'DELETE FROM accounts WHERE account_number = $1',
        [accountNumber]
      );
    });
  });
});