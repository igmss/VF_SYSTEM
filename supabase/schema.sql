-- Step 2: Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_cron"; -- Note: pg_cron may require enabling via Dashboard first

-- Step 3: Create Tables (in dependency order)

-- 3.1 users
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid TEXT UNIQUE,
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  role TEXT CHECK (role IN ('ADMIN','FINANCE','COLLECTOR','RETAILER')),
  is_active BOOLEAN DEFAULT true,
  retailer_id UUID,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3.2 bank_accounts
CREATE TABLE IF NOT EXISTS bank_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_holder TEXT,
  account_number TEXT,
  balance NUMERIC(15,4) DEFAULT 0,
  bank_name TEXT,
  is_default_for_buy BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  last_updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3.3 mobile_numbers
CREATE TABLE IF NOT EXISTS mobile_numbers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number TEXT UNIQUE,
  initial_balance NUMERIC(15,4) DEFAULT 0,
  in_total_used NUMERIC(15,4) DEFAULT 0,
  out_total_used NUMERIC(15,4) DEFAULT 0,
  in_daily_used NUMERIC(15,4) DEFAULT 0,
  in_daily_limit NUMERIC(15,4) DEFAULT 100000,
  out_daily_used NUMERIC(15,4) DEFAULT 0,
  out_daily_limit NUMERIC(15,4) DEFAULT 100000,
  in_monthly_used NUMERIC(15,4) DEFAULT 0,
  in_monthly_limit NUMERIC(15,4) DEFAULT 1000000,
  out_monthly_used NUMERIC(15,4) DEFAULT 0,
  out_monthly_limit NUMERIC(15,4) DEFAULT 1000000,
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  last_updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3.4 retailers
CREATE TABLE IF NOT EXISTS retailers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  phone TEXT,
  assigned_collector_id TEXT,
  discount_per_1000 NUMERIC,
  insta_pay_profit_per_1000 NUMERIC,
  total_assigned NUMERIC(15,4) DEFAULT 0,
  total_collected NUMERIC(15,4) DEFAULT 0,
  insta_pay_total_assigned NUMERIC(15,4) DEFAULT 0,
  insta_pay_total_collected NUMERIC(15,4) DEFAULT 0,
  insta_pay_pending_debt NUMERIC(15,4) DEFAULT 0,
  pending_debt NUMERIC(15,4) DEFAULT 0,
  credit NUMERIC(15,4) DEFAULT 0,
  area TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  last_updated_at TIMESTAMPTZ DEFAULT now()
);

-- Add foreign key constraint to users after retailers is created
ALTER TABLE users ADD CONSTRAINT fk_users_retailer FOREIGN KEY (retailer_id) REFERENCES retailers(id);


-- 3.5 collectors
CREATE TABLE IF NOT EXISTS collectors (
  id TEXT PRIMARY KEY, -- Firebase Auth UID
  uid TEXT,
  name TEXT,
  phone TEXT,
  email TEXT,
  cash_on_hand NUMERIC(15,4) DEFAULT 0,
  cash_limit NUMERIC(15,4) DEFAULT 50000,
  total_collected NUMERIC(15,4) DEFAULT 0,
  total_deposited NUMERIC(15,4) DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  last_updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3.6 investors
CREATE TABLE IF NOT EXISTS investors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  phone TEXT,
  invested_amount NUMERIC(15,4),
  half_invested_amount NUMERIC(15,4),
  initial_business_capital NUMERIC(15,4),
  cumulative_capital_before NUMERIC(15,4),
  half_cumulative_capital NUMERIC(15,4),
  profit_share_percent NUMERIC,
  investment_date BIGINT,
  period_days INT,
  status TEXT,
  total_profit_paid NUMERIC(15,4) DEFAULT 0,
  capital_history JSONB DEFAULT '{}',
  notes TEXT,
  created_by_uid TEXT,
  created_at BIGINT,
  last_paid_at BIGINT
);

-- 3.7 loans
CREATE TABLE IF NOT EXISTS loans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  borrower_name TEXT,
  borrower_phone TEXT,
  principal_amount NUMERIC(15,4),
  amount_repaid NUMERIC(15,4) DEFAULT 0,
  source_type TEXT,
  source_id TEXT,
  source_label TEXT,
  status TEXT,
  issued_at BIGINT,
  repaid_at BIGINT,
  last_updated_at BIGINT,
  notes TEXT,
  created_by_uid TEXT
);

-- 3.8 transactions
CREATE TABLE IF NOT EXISTS transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number TEXT,
  amount NUMERIC(15,4),
  currency TEXT DEFAULT 'EGP',
  timestamp TIMESTAMPTZ DEFAULT now(),
  bybit_order_id TEXT UNIQUE,
  status TEXT,
  payment_method TEXT,
  side SMALLINT,
  chat_history TEXT,
  price NUMERIC,
  quantity NUMERIC,
  token TEXT,
  related_ledger_id UUID
);

-- 3.9 financial_ledger
CREATE TABLE IF NOT EXISTS financial_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL,
  amount NUMERIC(15,4),
  from_id TEXT,
  from_label TEXT,
  to_id TEXT,
  to_label TEXT,
  created_by_uid TEXT,
  notes TEXT,
  timestamp BIGINT,
  bybit_order_id TEXT,
  related_ledger_id UUID,
  generated_transaction_id UUID,
  transferred_amount NUMERIC,
  fee_amount NUMERIC,
  fee_rate_per_1000 NUMERIC,
  collected_portion NUMERIC,
  credit_portion NUMERIC,
  usdt_price NUMERIC,
  usdt_quantity NUMERIC,
  profit_per_1000 NUMERIC,
  category TEXT,
  payment_method TEXT
);

-- 3.10 usd_exchange
CREATE TABLE IF NOT EXISTS usd_exchange (
  id INT PRIMARY KEY DEFAULT 1,
  usdt_balance NUMERIC(15,6) DEFAULT 0,
  last_price NUMERIC,
  last_updated_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT single_row CHECK (id = 1)
);

-- 3.11 sync_state
CREATE TABLE IF NOT EXISTS sync_state (
  id INT PRIMARY KEY DEFAULT 1,
  last_synced_order_ts BIGINT DEFAULT 0,
  last_sync_time BIGINT,
  last_server_sync_status TEXT,
  CONSTRAINT single_row CHECK (id = 1)
);

-- 3.12 system_config
CREATE TABLE IF NOT EXISTS system_config (
  key TEXT PRIMARY KEY,
  value JSONB
);

-- 3.13 partners
CREATE TABLE IF NOT EXISTS partners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  share_percent NUMERIC,
  status TEXT,
  total_profit_paid NUMERIC(15,4) DEFAULT 0,
  created_at BIGINT,
  updated_at BIGINT,
  last_paid_at BIGINT
);

-- 3.14 daily_flow_summary
CREATE TABLE IF NOT EXISTS daily_flow_summary (
  date_key TEXT PRIMARY KEY,
  vf_amount NUMERIC(15,4) DEFAULT 0,
  insta_amount NUMERIC(15,4) DEFAULT 0
);

-- 3.15 daily_stats
CREATE TABLE IF NOT EXISTS daily_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  year INT,
  month INT,
  day INT,
  collector_id TEXT,
  collections INT DEFAULT 0,
  expenses INT DEFAULT 0,
  profit NUMERIC DEFAULT 0,
  total_collections NUMERIC DEFAULT 0,
  total_expenses INT DEFAULT 0,
  total_profit NUMERIC DEFAULT 0
);

-- Step 4: Create Indexes
CREATE INDEX IF NOT EXISTS idx_transactions_bybit_order_id ON transactions(bybit_order_id);
CREATE INDEX IF NOT EXISTS idx_transactions_phone_number ON transactions(phone_number);
CREATE INDEX IF NOT EXISTS idx_financial_ledger_related_ledger_id ON financial_ledger(related_ledger_id);
CREATE INDEX IF NOT EXISTS idx_financial_ledger_bybit_order_id ON financial_ledger(bybit_order_id);
CREATE INDEX IF NOT EXISTS idx_financial_ledger_type ON financial_ledger(type);
CREATE INDEX IF NOT EXISTS idx_financial_ledger_timestamp ON financial_ledger(timestamp);
CREATE INDEX IF NOT EXISTS idx_financial_ledger_created_by_uid ON financial_ledger(created_by_uid);
CREATE INDEX IF NOT EXISTS idx_retailers_assigned_collector_id ON retailers(assigned_collector_id);
CREATE INDEX IF NOT EXISTS idx_loans_status ON loans(status);
CREATE INDEX IF NOT EXISTS idx_investors_status ON investors(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_stats_unique_collector_day ON daily_stats(year, month, day, collector_id);

-- Step 4.1: Helper Functions for RLS (to avoid recursion and support Firebase UIDs)
DROP FUNCTION IF EXISTS public.get_my_user_info();
CREATE OR REPLACE FUNCTION public.get_my_user_info()
RETURNS TABLE (role TEXT, firebase_uid TEXT) AS $$
  SELECT role, firebase_uid FROM public.users 
  WHERE firebase_uid = auth.uid()::text OR id = auth.uid()
  LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE;

DROP FUNCTION IF EXISTS public.is_admin();
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users 
    WHERE (firebase_uid = auth.uid()::text OR id = auth.uid())
      AND role = 'ADMIN'
  );
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE;

DROP FUNCTION IF EXISTS public.has_role(TEXT[]);
CREATE OR REPLACE FUNCTION public.has_role(target_roles TEXT[])
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users 
    WHERE (firebase_uid = auth.uid()::text OR id = auth.uid())
      AND role = ANY(target_roles)
  );
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE;

DROP FUNCTION IF EXISTS public.get_my_firebase_uid();
CREATE OR REPLACE FUNCTION public.get_my_firebase_uid()
RETURNS TEXT AS $$
  SELECT firebase_uid FROM public.users 
  WHERE firebase_uid = auth.uid()::text OR id = auth.uid()
  LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE;



-- Step 5: Enable Row Level Security (RLS)

-- 5.1 Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE mobile_numbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE retailers ENABLE ROW LEVEL SECURITY;
ALTER TABLE collectors ENABLE ROW LEVEL SECURITY;
ALTER TABLE investors ENABLE ROW LEVEL SECURITY;
ALTER TABLE loans ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE financial_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE usd_exchange ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE partners ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_flow_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_stats ENABLE ROW LEVEL SECURITY;

-- 5.2 users table policies
DROP POLICY IF EXISTS "users_self_read" ON users;
CREATE POLICY "users_self_read" ON users
  FOR SELECT TO authenticated
  USING (firebase_uid = auth.uid()::text OR id = auth.uid());

DROP POLICY IF EXISTS "users_admin_read" ON users;
CREATE POLICY "users_admin_read" ON users
  FOR SELECT TO authenticated
  USING (public.is_admin());


-- 5.3 financial_ledger table policies
DROP POLICY IF EXISTS "ledger_admin_finance_read" ON financial_ledger;
CREATE POLICY "ledger_admin_finance_read" ON financial_ledger
  FOR SELECT TO authenticated
  USING (public.has_role(ARRAY['ADMIN','FINANCE']));

DROP POLICY IF EXISTS "ledger_collector_read" ON financial_ledger;
CREATE POLICY "ledger_collector_read" ON financial_ledger
  FOR SELECT TO authenticated
  USING (
    (created_by_uid = auth.uid()::text OR created_by_uid = public.get_my_firebase_uid())
    AND public.has_role(ARRAY['COLLECTOR'])
  );


-- 5.4 transactions table policies
DROP POLICY IF EXISTS "transactions_authenticated_read" ON transactions;
CREATE POLICY "transactions_authenticated_read" ON transactions
  FOR SELECT TO authenticated
  USING (true);

-- 5.5 All other tables — authenticated read, service role write
DROP POLICY IF EXISTS "bank_accounts_read" ON bank_accounts;
CREATE POLICY "bank_accounts_read" ON bank_accounts FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "mobile_numbers_read" ON mobile_numbers;
CREATE POLICY "mobile_numbers_read" ON mobile_numbers FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "retailers_read" ON retailers;
CREATE POLICY "retailers_read" ON retailers FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "collectors_read" ON collectors;
CREATE POLICY "collectors_read" ON collectors FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "investors_read" ON investors;
CREATE POLICY "investors_read" ON investors FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "loans_read" ON loans;
CREATE POLICY "loans_read" ON loans FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "usd_exchange_read" ON usd_exchange;
CREATE POLICY "usd_exchange_read" ON usd_exchange FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "sync_state_read" ON sync_state;
CREATE POLICY "sync_state_read" ON sync_state FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "system_config_read" ON system_config;
CREATE POLICY "system_config_read" ON system_config FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "partners_read" ON partners;
CREATE POLICY "partners_read" ON partners FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "daily_flow_summary_read" ON daily_flow_summary;
CREATE POLICY "daily_flow_summary_read" ON daily_flow_summary FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "daily_stats_read" ON daily_stats;
CREATE POLICY "daily_stats_read" ON daily_stats FOR SELECT TO authenticated USING (true);

