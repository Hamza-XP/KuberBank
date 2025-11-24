-- ================================================================
-- KuberBank Database Functions
-- Description: Stored procedures and functions for banking operations
-- ================================================================

-- ================================================================
-- TRANSACTION FUNCTIONS
-- ================================================================

-- Function: Process Deposit
CREATE OR REPLACE FUNCTION process_deposit(
    p_account_number VARCHAR(50),
    p_amount DECIMAL(15, 2),
    p_description TEXT DEFAULT 'Deposit',
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL
)
RETURNS TABLE(
    transaction_id BIGINT,
    new_balance DECIMAL(15, 2),
    reference_number UUID,
    status VARCHAR(20)
) AS $$
DECLARE
    v_account_id INTEGER;
    v_current_balance DECIMAL(15, 2);
    v_new_balance DECIMAL(15, 2);
    v_transaction_id BIGINT;
    v_reference UUID;
BEGIN
    -- Get account
    SELECT id, balance INTO v_account_id, v_current_balance
    FROM accounts
    WHERE account_number = p_account_number AND status = 'active';
    
    IF v_account_id IS NULL THEN
        RAISE EXCEPTION 'Account not found or inactive: %', p_account_number;
    END IF;
    
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Deposit amount must be positive';
    END IF;
    
    -- Calculate new balance
    v_new_balance := v_current_balance + p_amount;
    
    -- Create transaction
    INSERT INTO transactions (
        account_id, type, amount, description, status,
        balance_before, balance_after, ip_address, user_agent,
        created_at, completed_at
    ) VALUES (
        v_account_id, 'deposit', p_amount, p_description, 'completed',
        v_current_balance, v_new_balance, p_ip_address, p_user_agent,
        NOW(), NOW()
    ) RETURNING id, reference_number INTO v_transaction_id, v_reference;
    
    -- Update account balance
    UPDATE accounts
    SET balance = v_new_balance,
        last_transaction_at = NOW()
    WHERE id = v_account_id;
    
    -- Create alert for large deposits
    IF p_amount > 10000 THEN
        INSERT INTO alerts (
            user_id, account_id, type, severity, title, message
        ) SELECT
            user_id, v_account_id, 'large_transaction', 'info',
            'Large Deposit',
            format('A deposit of $%s was made to account %s', p_amount, p_account_number)
        FROM accounts WHERE id = v_account_id;
    END IF;
    
    RETURN QUERY SELECT v_transaction_id, v_new_balance, v_reference, 'completed'::VARCHAR(20);
END;
$$ LANGUAGE plpgsql;

-- Function: Process Withdrawal
CREATE OR REPLACE FUNCTION process_withdrawal(
    p_account_number VARCHAR(50),
    p_amount DECIMAL(15, 2),
    p_description TEXT DEFAULT 'Withdrawal',
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL
)
RETURNS TABLE(
    transaction_id BIGINT,
    new_balance DECIMAL(15, 2),
    reference_number UUID,
    status VARCHAR(20)
) AS $$
DECLARE
    v_account_id INTEGER;
    v_current_balance DECIMAL(15, 2);
    v_overdraft_limit DECIMAL(15, 2);
    v_new_balance DECIMAL(15, 2);
    v_transaction_id BIGINT;
    v_reference UUID;
    v_daily_limit DECIMAL(15, 2);
    v_daily_usage DECIMAL(15, 2);
BEGIN
    -- Get account
    SELECT id, balance, overdraft_limit 
    INTO v_account_id, v_current_balance, v_overdraft_limit
    FROM accounts
    WHERE account_number = p_account_number AND status = 'active';
    
    IF v_account_id IS NULL THEN
        RAISE EXCEPTION 'Account not found or inactive: %', p_account_number;
    END IF;
    
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Withdrawal amount must be positive';
    END IF;
    
    -- Check balance
    IF (v_current_balance - p_amount) < -v_overdraft_limit THEN
        RAISE EXCEPTION 'Insufficient funds. Balance: $%, Withdrawal: $%, Overdraft: $%', 
            v_current_balance, p_amount, v_overdraft_limit;
    END IF;
    
    -- Check daily limits
    SELECT amount, current_usage INTO v_daily_limit, v_daily_usage
    FROM account_limits
    WHERE account_id = v_account_id 
    AND limit_type = 'daily_withdrawal'
    AND (reset_at IS NULL OR reset_at > NOW());
    
    IF FOUND AND (v_daily_usage + p_amount) > v_daily_limit THEN
        RAISE EXCEPTION 'Daily withdrawal limit exceeded. Limit: $%, Used: $%, Requested: $%',
            v_daily_limit, v_daily_usage, p_amount;
    END IF;
    
    -- Calculate new balance
    v_new_balance := v_current_balance - p_amount;
    
    -- Create transaction
    INSERT INTO transactions (
        account_id, type, amount, description, status,
        balance_before, balance_after, ip_address, user_agent,
        created_at, completed_at
    ) VALUES (
        v_account_id, 'withdrawal', p_amount, p_description, 'completed',
        v_current_balance, v_new_balance, p_ip_address, p_user_agent,
        NOW(), NOW()
    ) RETURNING id, reference_number INTO v_transaction_id, v_reference;
    
    -- Update account balance
    UPDATE accounts
    SET balance = v_new_balance,
        last_transaction_at = NOW()
    WHERE id = v_account_id;
    
    -- Update daily limit usage
    UPDATE account_limits
    SET current_usage = current_usage + p_amount
    WHERE account_id = v_account_id AND limit_type = 'daily_withdrawal';
    
    -- Create low balance alert
    IF v_new_balance < 100 THEN
        INSERT INTO alerts (
            user_id, account_id, type, severity, title, message
        ) SELECT
            user_id, v_account_id, 'low_balance', 'warning',
            'Low Balance Alert',
            format('Your account %s balance is $%s', p_account_number, v_new_balance)
        FROM accounts WHERE id = v_account_id;
    END IF;
    
    RETURN QUERY SELECT v_transaction_id, v_new_balance, v_reference, 'completed'::VARCHAR(20);
END;
$$ LANGUAGE plpgsql;

-- Function: Process Transfer
CREATE OR REPLACE FUNCTION process_transfer(
    p_from_account VARCHAR(50),
    p_to_account VARCHAR(50),
    p_amount DECIMAL(15, 2),
    p_description TEXT DEFAULT 'Transfer',
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL
)
RETURNS TABLE(
    from_transaction_id BIGINT,
    to_transaction_id BIGINT,
    from_balance DECIMAL(15, 2),
    to_balance DECIMAL(15, 2),
    reference_number UUID,
    status VARCHAR(20)
) AS $$
DECLARE
    v_from_account_id INTEGER;
    v_to_account_id INTEGER;
    v_from_balance DECIMAL(15, 2);
    v_to_balance DECIMAL(15, 2);
    v_from_new_balance DECIMAL(15, 2);
    v_to_new_balance DECIMAL(15, 2);
    v_from_tx_id BIGINT;
    v_to_tx_id BIGINT;
    v_reference UUID;
BEGIN
    -- Validate accounts
    IF p_from_account = p_to_account THEN
        RAISE EXCEPTION 'Cannot transfer to the same account';
    END IF;
    
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be positive';
    END IF;
    
    -- Get accounts (lock for update to prevent race conditions)
    SELECT id, balance INTO v_from_account_id, v_from_balance
    FROM accounts
    WHERE account_number = p_from_account AND status = 'active'
    FOR UPDATE;
    
    SELECT id, balance INTO v_to_account_id, v_to_balance
    FROM accounts
    WHERE account_number = p_to_account AND status = 'active'
    FOR UPDATE;
    
    IF v_from_account_id IS NULL THEN
        RAISE EXCEPTION 'Source account not found: %', p_from_account;
    END IF;
    
    IF v_to_account_id IS NULL THEN
        RAISE EXCEPTION 'Destination account not found: %', p_to_account;
    END IF;
    
    -- Check balance
    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient funds for transfer. Balance: $%, Required: $%',
            v_from_balance, p_amount;
    END IF;
    
    -- Generate reference
    v_reference := uuid_generate_v4();
    
    -- Calculate new balances
    v_from_new_balance := v_from_balance - p_amount;
    v_to_new_balance := v_to_balance + p_amount;
    
    -- Create withdrawal transaction
    INSERT INTO transactions (
        account_id, type, amount, description, status,
        balance_before, balance_after, reference_number,
        related_account_id, ip_address, user_agent,
        created_at, completed_at
    ) VALUES (
        v_from_account_id, 'withdrawal', p_amount,
        format('Transfer to %s: %s', p_to_account, p_description),
        'completed', v_from_balance, v_from_new_balance, v_reference,
        v_to_account_id, p_ip_address, p_user_agent,
        NOW(), NOW()
    ) RETURNING id INTO v_from_tx_id;
    
    -- Create deposit transaction
    INSERT INTO transactions (
        account_id, type, amount, description, status,
        balance_before, balance_after, reference_number,
        related_account_id, related_transaction_id, ip_address, user_agent,
        created_at, completed_at
    ) VALUES (
        v_to_account_id, 'deposit', p_amount,
        format('Transfer from %s: %s', p_from_account, p_description),
        'completed', v_to_balance, v_to_new_balance, v_reference,
        v_from_account_id, v_from_tx_id, p_ip_address, p_user_agent,
        NOW(), NOW()
    ) RETURNING id INTO v_to_tx_id;
    
    -- Update from account
    UPDATE accounts
    SET balance = v_from_new_balance,
        last_transaction_at = NOW()
    WHERE id = v_from_account_id;
    
    -- Update to account
    UPDATE accounts
    SET balance = v_to_new_balance,
        last_transaction_at = NOW()
    WHERE id = v_to_account_id;
    
    -- Create notification for recipient
    INSERT INTO alerts (
        user_id, account_id, type, severity, title, message
    ) SELECT
        user_id, v_to_account_id, 'transfer_received', 'info',
        'Transfer Received',
        format('You received $%s from account %s', p_amount, p_from_account)
    FROM accounts WHERE id = v_to_account_id;
    
    RETURN QUERY SELECT v_from_tx_id, v_to_tx_id, v_from_new_balance, 
                        v_to_new_balance, v_reference, 'completed'::VARCHAR(20);
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- ACCOUNT MANAGEMENT FUNCTIONS
-- ================================================================

-- Function: Create New Account
CREATE OR REPLACE FUNCTION create_account(
    p_user_id INTEGER,
    p_account_type VARCHAR(20) DEFAULT 'checking',
    p_initial_balance DECIMAL(15, 2) DEFAULT 0.00
)
RETURNS TABLE(
    account_id INTEGER,
    account_number VARCHAR(50),
    balance DECIMAL(15, 2),
    status VARCHAR(20)
) AS $$
DECLARE
    v_account_id INTEGER;
    v_account_number VARCHAR(50);
    v_user_exists BOOLEAN;
BEGIN
    -- Check if user exists
    SELECT EXISTS(SELECT 1 FROM users WHERE id = p_user_id) INTO v_user_exists;
    
    IF NOT v_user_exists THEN
        RAISE EXCEPTION 'User ID % does not exist', p_user_id;
    END IF;
    
    IF p_initial_balance < 0 THEN
        RAISE EXCEPTION 'Initial balance cannot be negative';
    END IF;
    
    -- Generate account number
    v_account_number := format('KB%s%s', 
        to_char(NOW(), 'YYYYMMDDHH24MISS'),
        lpad((floor(random() * 10000))::TEXT, 4, '0')
    );
    
    -- Create account
    INSERT INTO accounts (user_id, account_number, account_type, balance, status)
    VALUES (p_user_id, v_account_number, p_account_type, p_initial_balance, 'active')
    RETURNING id INTO v_account_id;
    
    -- Create initial deposit transaction if balance > 0
    IF p_initial_balance > 0 THEN
        INSERT INTO transactions (
            account_id, type, amount, description, status,
            balance_before, balance_after, created_at, completed_at
        ) VALUES (
            v_account_id, 'deposit', p_initial_balance, 'Initial deposit', 'completed',
            0.00, p_initial_balance, NOW(), NOW()
        );
    END IF;
    
    -- Set default limits
    INSERT INTO account_limits (account_id, limit_type, amount, period)
    VALUES 
        (v_account_id, 'daily_withdrawal', 1000.00, 'daily'),
        (v_account_id, 'daily_transfer', 5000.00, 'daily'),
        (v_account_id, 'single_transaction', 2000.00, 'transaction');
    
    -- Create audit log
    INSERT INTO audit_logs (user_id, account_id, action, entity_type, entity_id, new_values)
    VALUES (
        p_user_id, v_account_id, 'account_created', 'account', v_account_id,
        jsonb_build_object('account_number', v_account_number, 'type', p_account_type, 'balance', p_initial_balance)
    );
    
    RETURN QUERY SELECT v_account_id, v_account_number, p_initial_balance, 'active'::VARCHAR(20);
END;
$$ LANGUAGE plpgsql;

-- Function: Close Account
CREATE OR REPLACE FUNCTION close_account(
    p_account_number VARCHAR(50),
    p_reason TEXT DEFAULT 'Customer request'
)
RETURNS BOOLEAN AS $$
DECLARE
    v_account_id INTEGER;
    v_balance DECIMAL(15, 2);
    v_user_id INTEGER;
BEGIN
    -- Get account
    SELECT id, balance, user_id INTO v_account_id, v_balance, v_user_id
    FROM accounts
    WHERE account_number = p_account_number AND status = 'active';
    
    IF v_account_id IS NULL THEN
        RAISE EXCEPTION 'Account not found or already closed: %', p_account_number;
    END IF;
    
    IF v_balance != 0 THEN
        RAISE EXCEPTION 'Cannot close account with non-zero balance: $%', v_balance;
    END IF;
    
    -- Close account
    UPDATE accounts
    SET status = 'closed',
        closed_at = NOW()
    WHERE id = v_account_id;
    
    -- Create audit log
    INSERT INTO audit_logs (
        user_id, account_id, action, entity_type, entity_id,
        old_values, new_values, metadata
    ) VALUES (
        v_user_id, v_account_id, 'account_closed', 'account', v_account_id,
        jsonb_build_object('status', 'active'),
        jsonb_build_object('status', 'closed', 'closed_at', NOW()),
        jsonb_build_object('reason', p_reason)
    );
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- UTILITY FUNCTIONS
-- ================================================================

-- Function: Get Account Balance
CREATE OR REPLACE FUNCTION get_account_balance(p_account_number VARCHAR(50))
RETURNS DECIMAL(15, 2) AS $$
DECLARE
    v_balance DECIMAL(15, 2);
BEGIN
    SELECT balance INTO v_balance
    FROM accounts
    WHERE account_number = p_account_number AND status = 'active';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account not found: %', p_account_number;
    END IF;
    
    RETURN v_balance;
END;
$$ LANGUAGE plpgsql;

-- Function: Get Transaction History
CREATE OR REPLACE FUNCTION get_transaction_history(
    p_account_number VARCHAR(50),
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    transaction_id BIGINT,
    type VARCHAR(20),
    amount DECIMAL(15, 2),
    description TEXT,
    status VARCHAR(20),
    balance_after DECIMAL(15, 2),
    created_at TIMESTAMP WITH TIME ZONE,
    reference_number UUID
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.id,
        t.type,
        t.amount,
        t.description,
        t.status,
        t.balance_after,
        t.created_at,
        t.reference_number
    FROM transactions t
    JOIN accounts a ON t.account_id = a.id
    WHERE a.account_number = p_account_number
    ORDER BY t.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;

-- Function: Calculate Interest
CREATE OR REPLACE FUNCTION calculate_interest(p_account_number VARCHAR(50))
RETURNS DECIMAL(15, 2) AS $$
DECLARE
    v_balance DECIMAL(15, 2);
    v_rate DECIMAL(5, 4);
    v_interest DECIMAL(15, 2);
BEGIN
    SELECT balance, interest_rate INTO v_balance, v_rate
    FROM accounts
    WHERE account_number = p_account_number AND status = 'active';
    
    IF NOT FOUND THEN
        RETURN 0;
    END IF;
    
    -- Calculate monthly interest
    v_interest := v_balance * v_rate / 12;
    
    RETURN ROUND(v_interest, 2);
END;
$$ LANGUAGE plpgsql;

-- Function: Reset Daily Limits
CREATE OR REPLACE FUNCTION reset_daily_limits()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE account_limits
    SET current_usage = 0.00,
        reset_at = NOW() + INTERVAL '1 day'
    WHERE period = 'daily' 
    AND (reset_at IS NULL OR reset_at <= NOW());
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- REPORTING FUNCTIONS
-- ================================================================

-- Function: Get Account Summary
CREATE OR REPLACE FUNCTION get_account_summary(p_account_number VARCHAR(50))
RETURNS TABLE(
    account_number VARCHAR(50),
    account_type VARCHAR(20),
    balance DECIMAL(15, 2),
    total_deposits DECIMAL(15, 2),
    total_withdrawals DECIMAL(15, 2),
    transaction_count BIGINT,
    last_transaction TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.account_number,
        a.account_type,
        a.balance,
        COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'deposit' AND t.status = 'completed'), 0),
        COALESCE(SUM(t.amount) FILTER (WHERE t.type = 'withdrawal' AND t.status = 'completed'), 0),
        COUNT(t.id) FILTER (WHERE t.status = 'completed'),
        MAX(t.created_at)
    FROM accounts a
    LEFT JOIN transactions t ON a.id = t.account_id
    WHERE a.account_number = p_account_number
    GROUP BY a.account_number, a.account_type, a.balance;
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- COMMENTS
-- ================================================================

COMMENT ON FUNCTION process_deposit IS 'Process a deposit transaction with validation and audit trail';
COMMENT ON FUNCTION process_withdrawal IS 'Process a withdrawal with balance and limit checks';
COMMENT ON FUNCTION process_transfer IS 'Process a transfer between two accounts atomically';
COMMENT ON FUNCTION create_account IS 'Create a new bank account with default limits';
COMMENT ON FUNCTION close_account IS 'Close an account after validation';
COMMENT ON FUNCTION get_transaction_history IS 'Retrieve paginated transaction history';
COMMENT ON FUNCTION calculate_interest IS 'Calculate monthly interest for an account';
COMMENT ON FUNCTION reset_daily_limits IS 'Reset all daily transaction limits';

-- ================================================================
-- COMPLETION MESSAGE
-- ================================================================

DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'KuberBank Database Functions Created Successfully!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Transaction Functions: process_deposit, process_withdrawal, process_transfer';
    RAISE NOTICE 'Account Functions: create_account, close_account, get_account_balance';
    RAISE NOTICE 'Utility Functions: get_transaction_history, calculate_interest, reset_daily_limits';
    RAISE NOTICE 'Reporting Functions: get_account_summary';
    RAISE NOTICE '================================================================';
END $$;