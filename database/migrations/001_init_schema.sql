-- ================================================================
-- KuberBank Database Schema - Initial Migration
-- Version: 001
-- Description: Core banking schema with users, accounts, transactions
-- Compatible with: PostgreSQL 15+
-- ================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ================================================================
-- USERS TABLE
-- ================================================================
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    date_of_birth DATE,
    address TEXT,
    city VARCHAR(100),
    state VARCHAR(50),
    zip_code VARCHAR(20),
    country VARCHAR(50) DEFAULT 'USA',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT valid_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Index for email lookups
CREATE INDEX idx_users_email ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_created_at ON users(created_at DESC);
CREATE INDEX idx_users_deleted_at ON users(deleted_at) WHERE deleted_at IS NOT NULL;

-- ================================================================
-- ACCOUNTS TABLE
-- ================================================================
CREATE TABLE IF NOT EXISTS accounts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_number VARCHAR(50) UNIQUE NOT NULL,
    account_type VARCHAR(20) DEFAULT 'savings' CHECK (account_type IN ('savings', 'checking', 'business')),
    balance DECIMAL(15, 2) DEFAULT 0.00 NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'frozen', 'closed', 'pending')),
    overdraft_limit DECIMAL(15, 2) DEFAULT 0.00,
    interest_rate DECIMAL(5, 4) DEFAULT 0.0000,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    closed_at TIMESTAMP WITH TIME ZONE,
    last_transaction_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT positive_balance CHECK (balance >= -overdraft_limit),
    CONSTRAINT valid_account_number CHECK (account_number ~ '^KB[0-9]{10,}$')
);

-- Indexes for accounts
CREATE INDEX idx_accounts_user_id ON accounts(user_id);
CREATE INDEX idx_accounts_account_number ON accounts(account_number);
CREATE INDEX idx_accounts_status ON accounts(status) WHERE status = 'active';
CREATE INDEX idx_accounts_created_at ON accounts(created_at DESC);
CREATE INDEX idx_accounts_balance ON accounts(balance);

-- ================================================================
-- TRANSACTIONS TABLE
-- ================================================================
CREATE TABLE IF NOT EXISTS transactions (
    id BIGSERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL CHECK (type IN ('deposit', 'withdrawal', 'transfer', 'fee', 'interest', 'refund')),
    amount DECIMAL(15, 2) NOT NULL,
    balance_before DECIMAL(15, 2),
    balance_after DECIMAL(15, 2),
    description TEXT,
    reference_number UUID DEFAULT uuid_generate_v4() UNIQUE,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'reversed', 'cancelled')),
    related_transaction_id BIGINT REFERENCES transactions(id),
    related_account_id INTEGER REFERENCES accounts(id),
    metadata JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,
    failure_reason TEXT,
    CONSTRAINT positive_amount CHECK (amount > 0)
);

-- Indexes for transactions
CREATE INDEX idx_transactions_account_id ON transactions(account_id);
CREATE INDEX idx_transactions_created_at ON transactions(created_at DESC);
CREATE INDEX idx_transactions_type ON transactions(type);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_reference_number ON transactions(reference_number);
CREATE INDEX idx_transactions_related_account ON transactions(related_account_id) WHERE related_account_id IS NOT NULL;
CREATE INDEX idx_transactions_completed_at ON transactions(completed_at DESC) WHERE completed_at IS NOT NULL;

-- Composite index for common queries
CREATE INDEX idx_transactions_account_status_date ON transactions(account_id, status, created_at DESC);

-- ================================================================
-- AUDIT LOGS TABLE
-- ================================================================
CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    account_id INTEGER REFERENCES accounts(id),
    transaction_id BIGINT REFERENCES transactions(id),
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id INTEGER,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    user_agent TEXT,
    session_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB
);

-- Indexes for audit logs
CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_audit_logs_account_id ON audit_logs(account_id) WHERE account_id IS NOT NULL;
CREATE INDEX idx_audit_logs_transaction_id ON audit_logs(transaction_id) WHERE transaction_id IS NOT NULL;
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);

-- ================================================================
-- SESSIONS TABLE
-- ================================================================
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    device_info JSONB,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_activity TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);

-- Indexes for sessions
CREATE INDEX idx_sessions_user_id ON sessions(user_id) WHERE is_active = TRUE;
CREATE INDEX idx_sessions_token_hash ON sessions(token_hash);
CREATE INDEX idx_sessions_expires_at ON sessions(expires_at) WHERE is_active = TRUE;
CREATE INDEX idx_sessions_last_activity ON sessions(last_activity DESC);

-- ================================================================
-- ALERTS TABLE
-- ================================================================
CREATE TABLE IF NOT EXISTS alerts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    account_id INTEGER REFERENCES accounts(id) ON DELETE CASCADE,
    transaction_id BIGINT REFERENCES transactions(id),
    type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) DEFAULT 'info' CHECK (severity IN ('info', 'warning', 'critical')),
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB
);

-- Indexes for alerts
CREATE INDEX idx_alerts_user_id ON alerts(user_id);
CREATE INDEX idx_alerts_account_id ON alerts(account_id) WHERE account_id IS NOT NULL;
CREATE INDEX idx_alerts_is_read ON alerts(is_read, created_at DESC);
CREATE INDEX idx_alerts_severity ON alerts(severity) WHERE is_read = FALSE;

-- ================================================================
-- ACCOUNT LIMITS TABLE
-- ================================================================
CREATE TABLE IF NOT EXISTS account_limits (
    id SERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    limit_type VARCHAR(50) NOT NULL CHECK (limit_type IN ('daily_withdrawal', 'daily_transfer', 'single_transaction', 'monthly_withdrawal')),
    amount DECIMAL(15, 2) NOT NULL,
    period VARCHAR(20) DEFAULT 'daily' CHECK (period IN ('daily', 'weekly', 'monthly', 'transaction')),
    current_usage DECIMAL(15, 2) DEFAULT 0.00,
    reset_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT positive_limit CHECK (amount > 0)
);

-- Indexes for account limits
CREATE INDEX idx_account_limits_account_id ON account_limits(account_id);
CREATE INDEX idx_account_limits_type ON account_limits(limit_type);

-- ================================================================
-- TRANSFER QUEUE TABLE (for async transfers)
-- ================================================================
CREATE TABLE IF NOT EXISTS transfer_queue (
    id BIGSERIAL PRIMARY KEY,
    from_account_id INTEGER NOT NULL REFERENCES accounts(id),
    to_account_id INTEGER NOT NULL REFERENCES accounts(id),
    amount DECIMAL(15, 2) NOT NULL,
    description TEXT,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    scheduled_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    processed_at TIMESTAMP WITH TIME ZONE,
    transaction_id BIGINT REFERENCES transactions(id),
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for transfer queue
CREATE INDEX idx_transfer_queue_status ON transfer_queue(status, scheduled_at);
CREATE INDEX idx_transfer_queue_accounts ON transfer_queue(from_account_id, to_account_id);

-- ================================================================
-- TRIGGERS AND FUNCTIONS
-- ================================================================

-- Function: Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to relevant tables
CREATE TRIGGER update_users_updated_at 
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_accounts_updated_at 
    BEFORE UPDATE ON accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_account_limits_updated_at 
    BEFORE UPDATE ON account_limits
    FOR EACH ROW EXECUTE FUNCTION update_account_limits_updated_at_column();

-- Function: Log account balance changes
CREATE OR REPLACE FUNCTION log_balance_change()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE' AND OLD.balance != NEW.balance) THEN
        INSERT INTO audit_logs (
            account_id, 
            action, 
            entity_type, 
            entity_id, 
            old_values, 
            new_values,
            created_at
        ) VALUES (
            NEW.id,
            'balance_change',
            'account',
            NEW.id,
            jsonb_build_object('balance', OLD.balance, 'updated_at', OLD.updated_at),
            jsonb_build_object('balance', NEW.balance, 'updated_at', NEW.updated_at),
            NOW()
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER account_balance_audit 
    AFTER UPDATE ON accounts
    FOR EACH ROW EXECUTE FUNCTION log_balance_change();

-- Function: Update last_transaction_at on accounts
CREATE OR REPLACE FUNCTION update_last_transaction()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT' AND NEW.status = 'completed') THEN
        UPDATE accounts 
        SET last_transaction_at = NEW.completed_at 
        WHERE id = NEW.account_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_account_last_transaction 
    AFTER INSERT OR UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION update_last_transaction();

-- Function: Validate transaction amount against account balance
CREATE OR REPLACE FUNCTION validate_transaction_amount()
RETURNS TRIGGER AS $$
DECLARE
    current_balance DECIMAL(15, 2);
    overdraft_limit DECIMAL(15, 2);
BEGIN
    IF NEW.type IN ('withdrawal', 'transfer') THEN
        SELECT balance, overdraft_limit INTO current_balance, overdraft_limit
        FROM accounts WHERE id = NEW.account_id;
        
        IF (current_balance - NEW.amount) < -overdraft_limit THEN
            RAISE EXCEPTION 'Insufficient funds: balance=%, amount=%, overdraft=%', 
                current_balance, NEW.amount, overdraft_limit;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_transaction 
    BEFORE INSERT ON transactions
    FOR EACH ROW EXECUTE FUNCTION validate_transaction_amount();

-- Function: Auto-cleanup expired sessions
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS void AS $$
BEGIN
    UPDATE sessions 
    SET is_active = FALSE 
    WHERE expires_at < NOW() AND is_active = TRUE;
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- VIEWS
-- ================================================================

-- View: Account Summary with User Details
CREATE OR REPLACE VIEW account_summaries AS
SELECT 
    a.id AS account_id,
    a.account_number,
    a.account_type,
    a.balance,
    a.currency,
    a.status,
    a.created_at AS account_created_at,
    u.id AS user_id,
    u.first_name,
    u.last_name,
    u.email,
    u.phone,
    COUNT(DISTINCT t.id) AS total_transactions,
    COUNT(DISTINCT t.id) FILTER (WHERE t.type = 'deposit' AND t.status = 'completed') AS total_deposits,
    COUNT(DISTINCT t.id) FILTER (WHERE t.type = 'withdrawal' AND t.status = 'completed') AS total_withdrawals,
    COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'deposit' AND t.status = 'completed'), 0) AS total_deposited,
    COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'withdrawal' AND t.status = 'completed'), 0) AS total_withdrawn,
    MAX(t.created_at) AS last_transaction_at
FROM accounts a
JOIN users u ON a.user_id = u.id
LEFT JOIN transactions t ON a.id = t.account_id
WHERE a.deleted_at IS NULL AND u.deleted_at IS NULL
GROUP BY a.id, a.account_number, a.account_type, a.balance, a.currency, a.status, 
         a.created_at, u.id, u.first_name, u.last_name, u.email, u.phone;

-- View: Daily Transaction Summary
CREATE OR REPLACE VIEW daily_transaction_summary AS
SELECT 
    DATE(created_at) AS transaction_date,
    account_id,
    type,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_amount,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount
FROM transactions
WHERE status = 'completed'
GROUP BY DATE(created_at), account_id, type;

-- View: Replication Status (for monitoring)
CREATE OR REPLACE VIEW replication_status AS
SELECT 
    client_addr,
    client_hostname,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state,
    EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()))::INT AS lag_seconds
FROM pg_stat_replication;

-- View: Database Health Metrics
CREATE OR REPLACE VIEW database_health AS
SELECT
    'connections' AS metric,
    COUNT(*)::TEXT AS value,
    NOW() AS measured_at
FROM pg_stat_activity
UNION ALL
SELECT
    'database_size',
    pg_size_pretty(pg_database_size(current_database())),
    NOW()
UNION ALL
SELECT
    'active_queries',
    COUNT(*)::TEXT,
    NOW()
FROM pg_stat_activity
WHERE state = 'active'
UNION ALL
SELECT
    'idle_connections',
    COUNT(*)::TEXT,
    NOW()
FROM pg_stat_activity
WHERE state = 'idle';

-- ================================================================
-- MONITORING USER
-- ================================================================

-- Create metrics user for Prometheus
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'metrics_user') THEN
        CREATE USER metrics_user WITH PASSWORD 'changeme';
    END IF;
END
$$;

GRANT CONNECT ON DATABASE kuberbank TO metrics_user;
GRANT USAGE ON SCHEMA public TO metrics_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO metrics_user;
GRANT SELECT ON pg_stat_replication TO metrics_user;
GRANT SELECT ON pg_stat_database TO metrics_user;
GRANT SELECT ON pg_stat_activity TO metrics_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO metrics_user;

-- ================================================================
-- COMMENTS (Documentation)
-- ================================================================

COMMENT ON TABLE users IS 'Core user information for KuberBank customers';
COMMENT ON TABLE accounts IS 'Bank accounts linked to users with balance tracking';
COMMENT ON TABLE transactions IS 'All financial transactions with complete audit trail';
COMMENT ON TABLE audit_logs IS 'Comprehensive audit log for compliance and security';
COMMENT ON TABLE sessions IS 'User session management for authentication';
COMMENT ON TABLE alerts IS 'User notifications and alerts';
COMMENT ON TABLE account_limits IS 'Transaction limits per account';
COMMENT ON TABLE transfer_queue IS 'Queue for async transfer processing';

COMMENT ON COLUMN accounts.balance IS 'Current account balance in specified currency';
COMMENT ON COLUMN accounts.overdraft_limit IS 'Maximum negative balance allowed';
COMMENT ON COLUMN transactions.reference_number IS 'Unique reference for transaction tracking';
COMMENT ON COLUMN transactions.balance_before IS 'Account balance before transaction';
COMMENT ON COLUMN transactions.balance_after IS 'Account balance after transaction';

-- ================================================================
-- GRANT PERMISSIONS
-- ================================================================

-- Grant permissions to bankuser
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO bankuser;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO bankuser;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO bankuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO bankuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO bankuser;

-- ================================================================
-- COMPLETION MESSAGE
-- ================================================================

DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'KuberBank Database Schema Initialized Successfully!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Tables created: users, accounts, transactions, audit_logs, sessions, alerts';
    RAISE NOTICE 'Views created: account_summaries, daily_transaction_summary, replication_status';
    RAISE NOTICE 'Triggers: updated_at, balance_audit, transaction_validation';
    RAISE NOTICE 'Ready for application use!';
    RAISE NOTICE '================================================================';
END $$;