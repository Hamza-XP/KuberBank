const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const promClient = require('prom-client');
const winston = require('winston');

// Prometheus metrics setup
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

const dbQueryDuration = new promClient.Histogram({
  name: 'db_query_duration_seconds',
  help: 'Duration of database queries in seconds',
  labelNames: ['query_type'],
  registers: [register]
});

const accountCreationCounter = new promClient.Counter({
  name: 'account_creations_total',
  help: 'Total number of account creations',
  registers: [register]
});

const transactionCounter = new promClient.Counter({
  name: 'transactions_total',
  help: 'Total number of transactions',
  labelNames: ['type'],
  registers: [register]
});

// Logger setup
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'error.log', level: 'error' }),
    new winston.transports.File({ filename: 'combined.log' })
  ]
});

const app = express();

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100
});
app.use('/api/', limiter);

// PgBouncer connection through connection pooling
const pool = new Pool({
  host: process.env.DB_HOST || 'pgbouncer-service',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'kuberbank',
  user: process.env.DB_USER || 'bankuser',
  password: process.env.DB_PASSWORD,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
  ssl: process.env.DB_SSL === 'true' ? {
    rejectUnauthorized: false
  } : false
});

// Request logging middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration.labels(req.method, req.route?.path || req.path, res.statusCode).observe(duration);
    logger.info({
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration: `${duration}s`,
      ip: req.ip
    });
  });
  next();
});

// Health check endpoints
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'healthy', database: 'connected' });
  } catch (error) {
    logger.error('Health check failed', { error: error.message });
    res.status(503).json({ status: 'unhealthy', database: 'disconnected' });
  }
});

app.get('/ready', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ status: 'not ready' });
  }
});

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// API Routes

// Create account
app.post('/api/accounts', async (req, res) => {
  const { firstName, lastName, email, initialDeposit } = req.body;
  const client = await pool.connect();
  
  try {
    const start = Date.now();
    await client.query('BEGIN');
    
    // Create user
    const userResult = await client.query(
      'INSERT INTO users (first_name, last_name, email, created_at) VALUES ($1, $2, $3, NOW()) RETURNING id',
      [firstName, lastName, email]
    );
    const userId = userResult.rows[0].id;
    
    // Create account
    const accountNumber = `KB${Date.now()}${Math.floor(Math.random() * 10000)}`;
    const accountResult = await client.query(
      'INSERT INTO accounts (user_id, account_number, balance, status) VALUES ($1, $2, $3, $4) RETURNING id, account_number',
      [userId, accountNumber, initialDeposit || 0, 'active']
    );
    
    // Record initial deposit if provided
    if (initialDeposit && initialDeposit > 0) {
      await client.query(
        'INSERT INTO transactions (account_id, type, amount, description, status) VALUES ($1, $2, $3, $4, $5)',
        [accountResult.rows[0].id, 'deposit', initialDeposit, 'Initial deposit', 'completed']
      );
      transactionCounter.labels('deposit').inc();
    }
    
    await client.query('COMMIT');
    
    const duration = (Date.now() - start) / 1000;
    dbQueryDuration.labels('account_creation').observe(duration);
    accountCreationCounter.inc();
    
    logger.info('Account created', { userId, accountNumber });
    res.status(201).json({
      success: true,
      data: {
        userId,
        accountNumber: accountResult.rows[0].account_number,
        balance: initialDeposit || 0
      }
    });
  } catch (error) {
    await client.query('ROLLBACK');
    logger.error('Account creation failed', { error: error.message });
    res.status(500).json({ success: false, error: 'Account creation failed' });
  } finally {
    client.release();
  }
});

// Get account details
app.get('/api/accounts/:accountNumber', async (req, res) => {
  const { accountNumber } = req.params;
  
  try {
    const start = Date.now();
    const result = await pool.query(
      `SELECT a.id, a.account_number, a.balance, a.status, a.created_at,
              u.first_name, u.last_name, u.email
       FROM accounts a
       JOIN users u ON a.user_id = u.id
       WHERE a.account_number = $1`,
      [accountNumber]
    );
    
    const duration = (Date.now() - start) / 1000;
    dbQueryDuration.labels('account_query').observe(duration);
    
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Account not found' });
    }
    
    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    logger.error('Account query failed', { error: error.message });
    res.status(500).json({ success: false, error: 'Query failed' });
  }
});

// Create transaction (deposit/withdrawal)
app.post('/api/transactions', async (req, res) => {
  const { accountNumber, type, amount, description } = req.body;
  const client = await pool.connect();
  
  try {
    const start = Date.now();
    await client.query('BEGIN');
    
    // Get account
    const accountResult = await client.query(
      'SELECT id, balance FROM accounts WHERE account_number = $1 FOR UPDATE',
      [accountNumber]
    );
    
    if (accountResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ success: false, error: 'Account not found' });
    }
    
    const account = accountResult.rows[0];
    let newBalance = account.balance;
    
    if (type === 'deposit') {
      newBalance += parseFloat(amount);
    } else if (type === 'withdrawal') {
      if (account.balance < amount) {
        await client.query('ROLLBACK');
        return res.status(400).json({ success: false, error: 'Insufficient funds' });
      }
      newBalance -= parseFloat(amount);
    } else {
      await client.query('ROLLBACK');
      return res.status(400).json({ success: false, error: 'Invalid transaction type' });
    }
    
    // Update balance
    await client.query(
      'UPDATE accounts SET balance = $1, updated_at = NOW() WHERE id = $2',
      [newBalance, account.id]
    );
    
    // Record transaction
    const txResult = await client.query(
      'INSERT INTO transactions (account_id, type, amount, description, status, created_at) VALUES ($1, $2, $3, $4, $5, NOW()) RETURNING id, created_at',
      [account.id, type, amount, description, 'completed']
    );
    
    await client.query('COMMIT');
    
    const duration = (Date.now() - start) / 1000;
    dbQueryDuration.labels('transaction').observe(duration);
    transactionCounter.labels(type).inc();
    
    logger.info('Transaction completed', { accountNumber, type, amount });
    res.status(201).json({
      success: true,
      data: {
        transactionId: txResult.rows[0].id,
        newBalance,
        timestamp: txResult.rows[0].created_at
      }
    });
  } catch (error) {
    await client.query('ROLLBACK');
    logger.error('Transaction failed', { error: error.message });
    res.status(500).json({ success: false, error: 'Transaction failed' });
  } finally {
    client.release();
  }
});

// Get transaction history
app.get('/api/accounts/:accountNumber/transactions', async (req, res) => {
  const { accountNumber } = req.params;
  const { limit = 50, offset = 0 } = req.query;
  
  try {
    const start = Date.now();
    const result = await pool.query(
      `SELECT t.id, t.type, t.amount, t.description, t.status, t.created_at
       FROM transactions t
       JOIN accounts a ON t.account_id = a.id
       WHERE a.account_number = $1
       ORDER BY t.created_at DESC
       LIMIT $2 OFFSET $3`,
      [accountNumber, limit, offset]
    );
    
    const duration = (Date.now() - start) / 1000;
    dbQueryDuration.labels('transaction_history').observe(duration);
    
    res.json({ success: true, data: result.rows });
  } catch (error) {
    logger.error('Transaction history query failed', { error: error.message });
    res.status(500).json({ success: false, error: 'Query failed' });
  }
});

// Transfer between accounts
app.post('/api/transfers', async (req, res) => {
  const { fromAccount, toAccount, amount, description } = req.body;
  const client = await pool.connect();
  
  try {
    const start = Date.now();
    await client.query('BEGIN');
    
    // Get both accounts with row locks
    const accountsResult = await client.query(
      'SELECT id, account_number, balance FROM accounts WHERE account_number = ANY($1) FOR UPDATE',
      [[fromAccount, toAccount]]
    );
    
    if (accountsResult.rows.length !== 2) {
      await client.query('ROLLBACK');
      return res.status(404).json({ success: false, error: 'One or both accounts not found' });
    }
    
    const from = accountsResult.rows.find(a => a.account_number === fromAccount);
    const to = accountsResult.rows.find(a => a.account_number === toAccount);
    
    if (from.balance < amount) {
      await client.query('ROLLBACK');
      return res.status(400).json({ success: false, error: 'Insufficient funds' });
    }
    
    // Update balances
    await client.query('UPDATE accounts SET balance = balance - $1 WHERE id = $2', [amount, from.id]);
    await client.query('UPDATE accounts SET balance = balance + $1 WHERE id = $2', [amount, to.id]);
    
    // Record transactions
    await client.query(
      'INSERT INTO transactions (account_id, type, amount, description, status) VALUES ($1, $2, $3, $4, $5)',
      [from.id, 'withdrawal', amount, `Transfer to ${toAccount}: ${description}`, 'completed']
    );
    await client.query(
      'INSERT INTO transactions (account_id, type, amount, description, status) VALUES ($1, $2, $3, $4, $5)',
      [to.id, 'deposit', amount, `Transfer from ${fromAccount}: ${description}`, 'completed']
    );
    
    await client.query('COMMIT');
    
    const duration = (Date.now() - start) / 1000;
    dbQueryDuration.labels('transfer').observe(duration);
    transactionCounter.labels('transfer').inc();
    
    logger.info('Transfer completed', { fromAccount, toAccount, amount });
    res.status(201).json({ success: true, message: 'Transfer completed' });
  } catch (error) {
    await client.query('ROLLBACK');
    logger.error('Transfer failed', { error: error.message });
    res.status(500).json({ success: false, error: 'Transfer failed' });
  } finally {
    client.release();
  }
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM signal received: closing HTTP server');
  pool.end(() => {
    logger.info('Database pool closed');
    process.exit(0);
  });
});

// const PORT = process.env.PORT || 3000;
// app.listen(PORT, () => {
//   logger.info(`KuberBank API server running on port ${PORT}`);
// });

// Export app for testing
module.exports = app;

// Only start server if not being imported for tests
if (require.main === module) {
  const PORT = process.env.PORT || 3000;
  const server = app.listen(PORT, () => {
    logger.info(`KuberBank API server running on port ${PORT}`);
  });

  // Graceful shutdown
  process.on('SIGTERM', () => {
    logger.info('SIGTERM signal received: closing HTTP server');
    server.close(() => {
      pool.end(() => {
        logger.info('Database pool closed');
        process.exit(0);
      });
    });
  });
}