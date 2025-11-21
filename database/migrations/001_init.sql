-- KuberBank Database Schema
-- PostgreSQL with High Availability setup

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    date_of_birth DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Accounts table
CREATE TABLE IF NOT EXISTS accounts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_number VARCHAR(50) UNIQUE NOT NULL,
    account_type VARCHAR(20) DEFAULT 'savings' CHECK (account_type IN ('savings', 'checking', 'business')),
    balance DECIMAL(15, 2) DEFAULT 0.00 CHECK (balance >= 0),
    currency VARCHAR(3) DEFAULT 'USD',
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'frozen', 'closed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    closed_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT positive_balance CHECK (balance >= 0)
);

-- Transactions table (partitioned by created_at for better performance)
CREATE TABLE IF NOT EXISTS transactions (
    id BIGSERIAL PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL CHECK (type IN ('deposit', 'withdrawal', 'transfer', 'fee', 'interest')),
    amount DECIMAL(15, 2) NOT NULL CHECK (amount > 0),
    balance_after DECIMAL(15, 2),
    description TEXT,
    reference_number UUID DEFAULT uuid_generate_v4(),
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'reversed')),
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE
);

-- Audit log for compliance
CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    account_id INTEGER REFERENCES accounts(id),
    action VARCHAR(50) NOT NULL,
    entity_type VARCHAR(50),
    entity_id INTEGER,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Session management for authentication
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_activity TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ip_address INET,
    user_agent TEXT
);

-- Alerts and notifications
CREATE TABLE IF NOT EXISTS alerts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    account_id INTEGER REFERENCES accounts(id),
    type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) DEFAULT 'info' CHECK (severity IN ('info', 'warning', 'critical')),
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_created_at ON users(created_at);

CREATE INDEX idx_accounts_user_id ON accounts(user_id);
CREATE INDEX idx_accounts_account_number ON accounts(account_number);
CREATE INDEX idx_accounts_status ON accounts(status);

CREATE INDEX idx_transactions_account_id ON transactions(account_id);
CREATE INDEX idx_transactions_created_at ON transactions(created_at DESC);
CREATE INDEX idx_transactions_type ON transactions(type);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_reference_number ON transactions(reference_number);

CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_account_id ON audit_logs(account_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);

CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_sessions_token_hash ON sessions(token_hash);
CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);

CREATE INDEX idx_alerts_user_id ON alerts(user_id);
CREATE INDEX idx_alerts_is_read ON alerts(is_read);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to relevant tables
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_accounts_updated_at BEFORE UPDATE ON accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to log account balance changes
CREATE OR REPLACE FUNCTION log_balance_change()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE' AND OLD.balance != NEW.balance) THEN
        INSERT INTO audit_logs (account_id, action, entity_type, entity_id, old_values, new_values)
        VALUES (
            NEW.id,
            'balance_change',
            'account',
            NEW.id,
            jsonb_build_object('balance', OLD.balance),
            jsonb_build_object('balance', NEW.balance)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER account_balance_audit AFTER UPDATE ON accounts
    FOR EACH ROW EXECUTE FUNCTION log_balance_change();

-- Function to automatically clean up expired sessions
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS void AS $$
BEGIN
    DELETE FROM sessions WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- Create a view for account summaries
CREATE OR REPLACE VIEW account_summaries AS
SELECT 
    a.id,
    a.account_number,
    a.balance,
    a.status,
    u.first_name,
    u.last_name,
    u.email,
    COUNT(t.id) as total_transactions,
    SUM(CASE WHEN t.type = 'deposit' THEN t.amount ELSE 0 END) as total_deposits,
    SUM(CASE WHEN t.type = 'withdrawal' THEN t.amount ELSE 0 END) as total_withdrawals,
    MAX(t.created_at) as last_transaction_at
FROM accounts a
JOIN users u ON a.user_id = u.id
LEFT JOIN transactions t ON a.id = t.account_id AND t.status = 'completed'
GROUP BY a.id, a.account_number, a.balance, a.status, u.first_name, u.last_name, u.email;

-- Create monitoring view for replication lag
CREATE OR REPLACE VIEW replication_status AS
SELECT 
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state,
    EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()))::INT as lag_seconds
FROM pg_stat_replication;

-- Grant permissions for monitoring user
CREATE USER IF NOT EXISTS metrics_user WITH PASSWORD 'changeme';
GRANT CONNECT ON DATABASE kuberbank TO metrics_user;
GRANT USAGE ON SCHEMA public TO metrics_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO metrics_user;
GRANT SELECT ON pg_stat_replication TO metrics_user;
GRANT SELECT ON pg_stat_database TO metrics_user;

-- Insert sample data for testing
INSERT INTO users (first_name, last_name, email, phone) VALUES
    ('John', 'Doe', 'john.doe@example.com', '+1-555-0101'),
    ('Jane', 'Smith', 'jane.smith@example.com', '+1-555-0102'),
    ('Bob', 'Johnson', 'bob.johnson@example.com', '+1-555-0103')
ON CONFLICT (email) DO NOTHING;

-- Create sample accounts
INSERT INTO accounts (user_id, account_number, account_type, balance) VALUES
    (1, 'KB20250001001', 'checking', 5000.00),
    (1, 'KB20250001002', 'savings', 15000.00),
    (2, 'KB20250002001', 'checking', 3500.00),
    (3, 'KB20250003001', 'business', 50000.00)
ON CONFLICT (account_number) DO NOTHING;

-- Create sample transactions
INSERT INTO transactions (account_id, type, amount, description, status, completed_at) VALUES
    (1, 'deposit', 1000.00, 'Initial deposit', 'completed', NOW() - INTERVAL '30 days'),
    (1, 'withdrawal', 200.00, 'ATM withdrawal', 'completed', NOW() - INTERVAL '15 days'),
    (2, 'deposit', 5000.00, 'Salary deposit', 'completed', NOW() - INTERVAL '20 days'),
    (3, 'deposit', 500.00, 'Transfer from savings', 'completed', NOW() - INTERVAL '5 days')
ON CONFLICT DO NOTHING;

COMMENT ON TABLE users IS 'Core user information for KuberBank customers';
COMMENT ON TABLE accounts IS 'Bank accounts linked to users';
COMMENT ON TABLE transactions IS 'All financial transactions with audit trail';
COMMENT ON TABLE audit_logs IS 'Comprehensive audit log for compliance and security';
COMMENT ON TABLE sessions IS 'User session management for authentication';
COMMENT ON TABLE alerts IS 'User notifications and alerts';