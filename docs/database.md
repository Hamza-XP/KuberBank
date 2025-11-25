# 🗄️ KuberBank Database

Complete database schema, migrations, functions, and utilities for the KuberBank application.

## 📁 Directory Structure

```
db/
├── migrations/           # Database schema migrations
│   └── 001_init_schema.sql
├── functions/           # Stored procedures and functions
│   └── 001_banking_functions.sql
├── seeds/              # Sample data for development
│   └── 001_seed_data.sql
├── scripts/            # Utility scripts
│   ├── init_db.sh      # Initialize database
│   ├── backup.sh       # Backup database
│   └── restore.sh      # Restore from backup
└── README.md           # This file
```

## 🚀 Quick Start

### Initialize Database

```bash
cd db/scripts

# Basic initialization
./init_db.sh

# With custom settings
DB_HOST=localhost DB_NAME=kuberbank DB_USER=bankuser ./init_db.sh

# Force reinitialization
./init_db.sh --force

# Initialize without seed data
./init_db.sh --skip-seeds
```

### Connect to Database

```bash
psql -h localhost -U bankuser -d kuberbank
```

## 📊 Database Schema

### Tables

#### users
Stores customer information
```sql
- id (SERIAL PRIMARY KEY)
- first_name, last_name
- email (UNIQUE)
- phone, date_of_birth
- address, city, state, zip_code, country
- created_at, updated_at, deleted_at
```

#### accounts
Bank accounts linked to users
```sql
- id (SERIAL PRIMARY KEY)
- user_id (FK → users)
- account_number (UNIQUE, format: KB + timestamp + random)
- account_type (savings/checking/business)
- balance (DECIMAL 15,2)
- currency (DEFAULT 'USD')
- status (active/frozen/closed/pending)
- overdraft_limit
- interest_rate
- created_at, updated_at, closed_at
```

#### transactions
All financial transactions
```sql
- id (BIGSERIAL PRIMARY KEY)
- account_id (FK → accounts)
- type (deposit/withdrawal/transfer/fee/interest/refund)
- amount (DECIMAL 15,2)
- balance_before, balance_after
- description
- reference_number (UUID, UNIQUE)
- status (pending/completed/failed/reversed/cancelled)
- related_transaction_id, related_account_id
- metadata (JSONB)
- created_at, completed_at, failed_at
```

#### audit_logs
Comprehensive audit trail for compliance
```sql
- id (BIGSERIAL PRIMARY KEY)
- user_id, account_id, transaction_id
- action (e.g., 'balance_change', 'account_created')
- entity_type, entity_id
- old_values, new_values (JSONB)
- ip_address, user_agent
- session_id
- created_at
```

#### sessions
User session management
```sql
- id (UUID PRIMARY KEY)
- user_id (FK → users)
- token_hash
- device_info (JSONB)
- ip_address, user_agent
- expires_at
- created_at, last_activity
- is_active
```

#### alerts
User notifications
```sql
- id (SERIAL PRIMARY KEY)
- user_id, account_id, transaction_id
- type (e.g., 'low_balance', 'large_transaction')
- severity (info/warning/critical)
- title, message
- is_read, read_at
- created_at
```

#### account_limits
Transaction limits per account
```sql
- id (SERIAL PRIMARY KEY)
- account_id (FK → accounts)
- limit_type (daily_withdrawal/daily_transfer/single_transaction)
- amount (DECIMAL 15,2)
- period (daily/weekly/monthly/transaction)
- current_usage
- reset_at
```

#### transfer_queue
Async transfer processing queue
```sql
- id (BIGSERIAL PRIMARY KEY)
- from_account_id, to_account_id
- amount (DECIMAL 15,2)
- description
- status (pending/processing/completed/failed)
- scheduled_at, processed_at
- transaction_id
- error_message
- retry_count
```

### Views

#### account_summaries
Comprehensive account overview with transaction statistics
```sql
SELECT * FROM account_summaries;
```

#### daily_transaction_summary
Daily aggregated transaction data
```sql
SELECT * FROM daily_transaction_summary 
WHERE transaction_date = CURRENT_DATE;
```

#### replication_status
PostgreSQL replication monitoring
```sql
SELECT * FROM replication_status;
```

#### database_health
Key database health metrics
```sql
SELECT * FROM database_health;
```

## 🔧 Database Functions

### Transaction Functions

#### process_deposit
Process a deposit with validation and audit trail
```sql
SELECT * FROM process_deposit(
    'KB2025010100001',  -- account_number
    500.00,             -- amount
    'Salary deposit'    -- description
);
```

#### process_withdrawal
Process a withdrawal with balance and limit checks
```sql
SELECT * FROM process_withdrawal(
    'KB2025010100001',  -- account_number
    100.00,             -- amount
    'ATM withdrawal'    -- description
);
```

#### process_transfer
Atomically transfer funds between accounts
```sql
SELECT * FROM process_transfer(
    'KB2025010100001',  -- from_account
    'KB2025010200001',  -- to_account
    250.00,             -- amount
    'Monthly transfer'  -- description
);
```

### Account Management Functions

#### create_account
Create a new bank account
```sql
SELECT * FROM create_account(
    1,            -- user_id
    'checking',   -- account_type
    1000.00       -- initial_balance
);
```

#### close_account
Close an account (must have zero balance)
```sql
SELECT close_account(
    'KB2025010100001',  -- account_number
    'Customer request'   -- reason
);
```

#### get_account_balance
Get current account balance
```sql
SELECT get_account_balance('KB2025010100001');
```

### Utility Functions

#### get_transaction_history
Retrieve paginated transaction history
```sql
SELECT * FROM get_transaction_history(
    'KB2025010100001',  -- account_number
    50,                 -- limit
    0                   -- offset
);
```

#### calculate_interest
Calculate monthly interest for an account
```sql
SELECT calculate_interest('KB2025010100001');
```

#### reset_daily_limits
Reset all daily transaction limits (runs via cron)
```sql
SELECT reset_daily_limits();
```

### Reporting Functions

#### get_account_summary
Get comprehensive account summary
```sql
SELECT * FROM get_account_summary('KB2025010100001');
```

## 🔄 Migrations

Migrations are versioned SQL files that define the database schema.

### Running Migrations

```bash
# Via init script
./scripts/init_db.sh

# Manually
psql -h localhost -U bankuser -d kuberbank -f migrations/001_init_schema.sql
```

### Creating New Migrations

1. Create a new file: `migrations/002_add_feature.sql`
2. Add your schema changes
3. Test on development database
4. Commit and deploy

## 🌱 Seed Data

Sample data for development and testing.

### Included Test Accounts

| Email | Account Number | Type | Balance |
|-------|----------------|------|---------|
| john.doe@example.com | KB2025010100001 | checking | $5,000 |
| john.doe@example.com | KB2025010100002 | savings | $15,000 |
| jane.smith@example.com | KB2025010200001 | checking | $3,500 |
| jane.smith@example.com | KB2025010200002 | savings | $25,000 |
| bob.johnson@example.com | KB2025010300001 | business | $50,000 |

### Loading Seed Data

```bash
# Via init script
./scripts/init_db.sh

# Skip seeds
./scripts/init_db.sh --skip-seeds

# Manually
psql -h localhost -U bankuser -d kuberbank -f seeds/001_seed_data.sql
```

## 💾 Backup & Restore

### Backup Database

```bash
cd db/scripts

# Basic backup
./backup.sh

# Backup to custom directory
./backup.sh -d /path/to/backups

# Backup and upload to S3
./backup.sh -s

# Custom retention (60 days)
./backup.sh -r 60

# Test mode
./backup.sh --test
```

### Restore Database

```bash
# Restore from local file
./restore.sh kuberbank_backup_20250125_120000.sql.gz

# Restore from S3
./restore.sh s3://bucket/backups/kuberbank_backup_20250125_120000.sql.gz

# Force restore without confirmation
./restore.sh backup.sql.gz --force

# Drop and recreate database
./restore.sh backup.sql.gz --drop
```

## 🔍 Monitoring Queries

### Check Database Size
```sql
SELECT pg_size_pretty(pg_database_size('kuberbank'));
```

### Active Connections
```sql
SELECT count(*) FROM pg_stat_activity WHERE datname = 'kuberbank';
```

### Table Sizes
```sql
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### Slow Queries
```sql
SELECT 
    query,
    calls,
    total_exec_time,
    mean_exec_time,
    max_exec_time
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### Index Usage
```sql
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

### Replication Lag (if using replication)
```sql
SELECT * FROM replication_status;
```

## 🧪 Testing

### Test Database Connection
```sql
SELECT version();
SELECT current_database();
SELECT current_user;
```

### Test Functions
```sql
-- Test deposit
SELECT * FROM process_deposit('KB2025010100001', 100.00, 'Test deposit');

-- Test balance check
SELECT get_account_balance('KB2025010100001');

-- Test transaction history
SELECT * FROM get_transaction_history('KB2025010100001', 10, 0);
```

### Verify Data Integrity
```sql
-- Check for orphaned records
SELECT COUNT(*) FROM accounts WHERE user_id NOT IN (SELECT id FROM users);

-- Check balance consistency
SELECT 
    a.account_number,
    a.balance AS current_balance,
    COALESCE(SUM(
        CASE 
            WHEN t.type IN ('deposit', 'interest', 'refund') THEN t.amount
            WHEN t.type IN ('withdrawal', 'transfer', 'fee') THEN -t.amount
            ELSE 0
        END
    ), 0) AS calculated_balance
FROM accounts a
LEFT JOIN transactions t ON a.id = t.account_id AND t.status = 'completed'
GROUP BY a.id, a.account_number, a.balance
HAVING a.balance != COALESCE(SUM(
    CASE 
        WHEN t.type IN ('deposit', 'interest', 'refund') THEN t.amount
        WHEN t.type IN ('withdrawal', 'transfer', 'fee') THEN -t.amount
        ELSE 0
    END
), 0);
```

## 🔐 Security

### User Permissions
```sql
-- Grant read-only access
CREATE USER readonly WITH PASSWORD 'readonly_password';
GRANT CONNECT ON DATABASE kuberbank TO readonly;
GRANT USAGE ON SCHEMA public TO readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly;

-- Grant monitoring access
GRANT pg_monitor TO metrics_user;
```

### Enable SSL
```bash
# In postgresql.conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_ca_file = 'root.crt'
```

### Row-Level Security (Example)
```sql
-- Enable RLS on accounts table
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;

-- Create policy
CREATE POLICY account_isolation ON accounts
    USING (user_id = current_setting('app.current_user_id')::integer);
```

## 📈 Performance Tuning

### Recommended Settings (postgresql.conf)
```ini
# Memory
shared_buffers = 1GB
effective_cache_size = 3GB
maintenance_work_mem = 256MB
work_mem = 32MB

# WAL
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 1GB

# Checkpoints
checkpoint_timeout = 15min
checkpoint_completion_target = 0.9

# Query Performance
random_page_cost = 1.1
effective_io_concurrency = 200
```

### Analyze Tables
```sql
ANALYZE VERBOSE;
```

### Vacuum
```sql
VACUUM ANALYZE;
```

## 🐛 Troubleshooting

### Connection Issues
```bash
# Check if PostgreSQL is running
systemctl status postgresql

# Check logs
tail -f /var/log/postgresql/postgresql-15-main.log

# Test connection
psql -h localhost -U bankuser -d kuberbank -c "SELECT 1"
```

### Reset Sequences
```sql
SELECT setval('users_id_seq', (SELECT MAX(id) FROM users));
SELECT setval('accounts_id_seq', (SELECT MAX(id) FROM accounts));
SELECT setval('transactions_id_seq', (SELECT MAX(id) FROM transactions));
```

### Deadlock Detection
```sql
SELECT * FROM pg_locks WHERE NOT granted;
```

### Kill Long-Running Queries
```sql
SELECT 
    pid,
    usename,
    state,
    query_start,
    query
FROM pg_stat_activity
WHERE state = 'active' AND query_start < NOW() - INTERVAL '5 minutes';

-- Kill specific query
SELECT pg_terminate_backend(12345);  -- Replace with actual PID
```

## 📚 Additional Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)
- [PostgreSQL High Availability](https://www.postgresql.org/docs/current/high-availability.html)

## 🤝 Contributing

When adding new database features:

1. Create migration file in `migrations/`
2. Add functions in `functions/`
3. Update seed data if needed
4. Update this README
5. Test thoroughly
6. Submit PR

---

**Database Version:** 1.0.0  
**PostgreSQL:** 15+  
**Last Updated:** 2025-01-25