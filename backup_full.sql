


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."acquire_sync_lock"("p_owner_id" "text", "p_ttl_ms" bigint) RETURNS TABLE("acquired" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO sync_locks (id, owner_id, acquired_at, expires_at)
  VALUES (1, p_owner_id, now(), now() + (p_ttl_ms || ' milliseconds')::interval)
  ON CONFLICT (id) DO UPDATE 
  SET owner_id = p_owner_id, 
      acquired_at = now(), 
      expires_at = now() + (p_ttl_ms || ' milliseconds')::interval 
  WHERE sync_locks.expires_at < now() OR sync_locks.owner_id = p_owner_id
  RETURNING TRUE INTO acquired;

  IF acquired IS TRUE THEN
    RETURN QUERY SELECT TRUE;
  ELSE
    RETURN QUERY SELECT FALSE;
  END IF;
END;
$$;


ALTER FUNCTION "public"."acquire_sync_lock"("p_owner_id" "text", "p_ttl_ms" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."apply_mobile_number_usage_delta"("p_number_id" "uuid", "p_amount_delta" numeric, "p_direction" "text", "p_timestamp_ms" bigint) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_today_start_ms BIGINT;
  v_month_start_ms BIGINT;
  v_prefix TEXT;
BEGIN
  -- Normalize direction and validate
  IF p_direction IN ('in', 'incoming') THEN
    v_prefix := 'in';
  ELSIF p_direction IN ('out', 'outgoing') THEN
    v_prefix := 'out';
  ELSE
    RAISE EXCEPTION 'Invalid direction: %. Expected ''in'' or ''out''.', p_direction;
  END IF;
  v_today_start_ms := (EXTRACT(EPOCH FROM (CURRENT_DATE AT TIME ZONE 'UTC')) * 1000)::BIGINT;
  v_month_start_ms := (EXTRACT(EPOCH FROM (DATE_TRUNC('month', CURRENT_DATE) AT TIME ZONE 'UTC')) * 1000)::BIGINT;

  IF v_prefix = 'in' THEN
    UPDATE mobile_numbers SET
      in_total_used = in_total_used + p_amount_delta,
      in_daily_used = CASE WHEN p_timestamp_ms >= v_today_start_ms THEN in_daily_used + p_amount_delta ELSE in_daily_used END,
      in_monthly_used = CASE WHEN p_timestamp_ms >= v_month_start_ms THEN in_monthly_used + p_amount_delta ELSE in_monthly_used END,
      last_updated_at = now()
    WHERE id = p_number_id;
  ELSE
    UPDATE mobile_numbers SET
      out_total_used = out_total_used + p_amount_delta,
      out_daily_used = CASE WHEN p_timestamp_ms >= v_today_start_ms THEN out_daily_used + p_amount_delta ELSE out_daily_used END,
      out_monthly_used = CASE WHEN p_timestamp_ms >= v_month_start_ms THEN out_monthly_used + p_amount_delta ELSE out_monthly_used END,
      last_updated_at = now()
    WHERE id = p_number_id;
  END IF;
END;
$$;


ALTER FUNCTION "public"."apply_mobile_number_usage_delta"("p_number_id" "uuid", "p_amount_delta" numeric, "p_direction" "text", "p_timestamp_ms" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."collect_retailer_cash_tx"("p_collector_id" "text", "p_retailer_id" "uuid", "p_amount" numeric, "p_vf_amount" numeric, "p_insta_pay_amount" numeric, "p_notes" "text", "p_added_to_collected" numeric, "p_added_to_credit" numeric, "p_uid" "text", "p_timestamp" bigint, "p_insta_tx_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("tx_id" "uuid", "insta_tx_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tx_id UUID := gen_random_uuid();
  v_insta_tx_id UUID := p_insta_tx_id;
BEGIN
  -- 1. Update collector balance
  UPDATE collectors 
  SET cash_on_hand = cash_on_hand + p_amount,
      total_collected = total_collected + p_amount,
      last_updated_at = now()
  WHERE id = p_collector_id;

  -- 2. Insert COLLECT_CASH ledger entry
  INSERT INTO financial_ledger (
    id, type, amount, from_id, from_label, to_id, to_label, 
    created_by_uid, notes, timestamp, collected_portion, credit_portion
  ) VALUES (
    v_tx_id, 'COLLECT_CASH', p_amount, p_retailer_id::text, NULL, p_collector_id, NULL,
    p_uid, p_notes, p_timestamp, p_added_to_collected, p_added_to_credit
  );

  -- 3. Update retailer (VF portion)
  IF p_added_to_collected > 0 OR p_added_to_credit > 0 THEN
    UPDATE retailers SET
      total_collected = total_collected + p_added_to_collected,
      credit = credit + p_added_to_credit,
      last_updated_at = now()
    WHERE id = p_retailer_id;
  END IF;

  -- 4. Handle InstaPay portion
  IF p_insta_pay_amount > 0 THEN
    -- Update retailer InstaPay balance
    UPDATE retailers SET
      insta_pay_total_collected = insta_pay_total_collected + p_insta_pay_amount,
      last_updated_at = now()
    WHERE id = p_retailer_id;

    -- Insert COLLECT_INSTAPAY_CASH ledger entry
    -- Use provided insta_tx_id or generate one
    IF v_insta_tx_id IS NULL THEN
      v_insta_tx_id := gen_random_uuid();
    END IF;

    INSERT INTO financial_ledger (
      id, type, amount, from_id, from_label, to_id, to_label, 
      created_by_uid, notes, timestamp
    ) VALUES (
      v_insta_tx_id, 'COLLECT_INSTAPAY_CASH', p_insta_pay_amount, p_retailer_id::text, NULL, p_collector_id, NULL,
      p_uid, p_notes, p_timestamp
    );
  END IF;

  RETURN QUERY SELECT v_tx_id, v_insta_tx_id;
END;
$$;


ALTER FUNCTION "public"."collect_retailer_cash_tx"("p_collector_id" "text", "p_retailer_id" "uuid", "p_amount" numeric, "p_vf_amount" numeric, "p_insta_pay_amount" numeric, "p_notes" "text", "p_added_to_collected" numeric, "p_added_to_credit" numeric, "p_uid" "text", "p_timestamp" bigint, "p_insta_tx_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."correct_financial_ledger_entry"("p_ledger_id" "uuid", "p_new_amount" numeric, "p_new_notes" "text", "p_created_by_uid" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_old RECORD;
  v_diff NUMERIC;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
BEGIN
  -- 1. Get old entry
  SELECT * INTO v_old FROM financial_ledger WHERE id = p_ledger_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ledger entry not found.';
  END IF;

  v_diff := p_new_amount - v_old.amount;

  -- 2. Update Ledger Entry
  UPDATE financial_ledger SET
    amount = p_new_amount,
    notes = p_new_notes || ' (Corrected from ' || v_old.amount || ')',
    created_by_uid = p_created_by_uid
  WHERE id = p_ledger_id;

  -- 3. Reverse Balance Impact (This is complex as it depends on the type)
  -- For now, we only handle common types that impact Bank or VF balance.
  
  IF v_old.type IN ('BUY_USDT', 'EXPENSE_BANK', 'LOAN_ISSUED', 'INVESTOR_PROFIT_PAID', 'PARTNER_PROFIT_PAID_BANK', 'INVESTOR_CAPITAL_OUT') THEN
    -- These were deductions from Bank. A positive diff means we deducted too little, so deduct more.
    UPDATE bank_accounts SET balance = balance - v_diff WHERE id = v_old.from_id::UUID;
  ELSIF v_old.type IN ('SELL_USDT', 'LOAN_REPAYMENT', 'INVESTOR_CAPITAL_IN') THEN
    -- These were additions to Bank. A positive diff means we added too little, so add more.
    UPDATE bank_accounts SET balance = balance + v_diff WHERE id = v_old.to_id::UUID;
  ELSIF v_old.type IN ('DISTRIBUTE_VFCASH') THEN
    -- This was a deduction from VF balance.
    PERFORM apply_mobile_number_usage_delta(v_old.from_id::UUID, v_diff, 'out', v_now_ts);
  ELSIF v_old.type IN ('PARTNER_PROFIT_PAID_VF') THEN
    -- This was a deduction from VF balance.
    PERFORM apply_mobile_number_usage_delta(v_old.from_id::UUID, v_diff, 'out', v_now_ts);
  END IF;

  -- 4. Log the correction
  INSERT INTO financial_ledger (
    type, amount, from_label, to_label, notes, created_by_uid, timestamp
  ) VALUES (
    'SYSTEM_CORRECTION', v_diff, 'Correction', 'Ledger ' || p_ledger_id,
    'Correction of entry ' || p_ledger_id || '. Diff: ' || v_diff,
    p_created_by_uid, v_now_ts
  );
END;
$$;


ALTER FUNCTION "public"."correct_financial_ledger_entry"("p_ledger_id" "uuid", "p_new_amount" numeric, "p_new_notes" "text", "p_created_by_uid" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."deduct_bank_balance"("p_bank_id" "uuid", "p_amount" numeric) RETURNS TABLE("committed" boolean, "new_balance" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_current_balance NUMERIC;
BEGIN
  UPDATE bank_accounts 
  SET balance = balance - p_amount,
      last_updated_at = now()
  WHERE id = p_bank_id AND balance >= p_amount
  RETURNING bank_accounts.balance INTO v_current_balance;

  IF FOUND THEN
    RETURN QUERY SELECT TRUE, v_current_balance;
  ELSE
    SELECT bank_accounts.balance INTO v_current_balance FROM bank_accounts WHERE id = p_bank_id;
    RETURN QUERY SELECT FALSE, v_current_balance;
  END IF;
END;
$$;


ALTER FUNCTION "public"."deduct_bank_balance"("p_bank_id" "uuid", "p_amount" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."deduct_collector_cash"("p_collector_id" "text", "p_amount" numeric) RETURNS TABLE("committed" boolean, "new_cash_on_hand" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_current_cash NUMERIC;
BEGIN
  UPDATE collectors 
  SET cash_on_hand = cash_on_hand - p_amount,
      last_updated_at = now()
  WHERE id = p_collector_id AND cash_on_hand >= p_amount
  RETURNING collectors.cash_on_hand INTO v_current_cash;

  IF FOUND THEN
    RETURN QUERY SELECT TRUE, v_current_cash;
  ELSE
    SELECT collectors.cash_on_hand INTO v_current_cash FROM collectors WHERE id = p_collector_id;
    RETURN QUERY SELECT FALSE, v_current_cash;
  END IF;
END;
$$;


ALTER FUNCTION "public"."deduct_collector_cash"("p_collector_id" "text", "p_amount" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."deposit_collector_cash_tx"("p_collector_id" "text", "p_bank_account_id" "uuid", "p_amount" numeric, "p_notes" "text", "p_uid" "text", "p_timestamp" bigint) RETURNS TABLE("committed" boolean, "tx_id" "uuid", "new_cash_on_hand" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tx_id UUID := gen_random_uuid();
  v_new_cash NUMERIC;
  v_collector_name TEXT;
  v_bank_name TEXT;
BEGIN
  -- 1. Deduct cash_on_hand — fail fast if insufficient
  UPDATE collectors
  SET cash_on_hand = cash_on_hand - p_amount,
      total_deposited = total_deposited + p_amount,
      last_updated_at = now()
  WHERE id = p_collector_id AND cash_on_hand >= p_amount
  RETURNING collectors.cash_on_hand, collectors.name INTO v_new_cash, v_collector_name;

  IF NOT FOUND THEN
    -- Return NOT committed with current cash level
    SELECT collectors.cash_on_hand INTO v_new_cash FROM collectors WHERE id = p_collector_id;
    RETURN QUERY SELECT FALSE, NULL::UUID, COALESCE(v_new_cash, 0::NUMERIC);
    RETURN;
  END IF;

  -- 2. Credit bank balance
  UPDATE bank_accounts
  SET balance = balance + p_amount,
      last_updated_at = now()
  WHERE id = p_bank_account_id
  RETURNING bank_name INTO v_bank_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bank account not found: %', p_bank_account_id;
  END IF;

  -- 3. Insert ledger entry
  INSERT INTO financial_ledger (
    id, type, amount, from_id, from_label, to_id, to_label,
    created_by_uid, notes, timestamp
  ) VALUES (
    v_tx_id, 'DEPOSIT_TO_BANK', p_amount,
    p_collector_id, COALESCE(v_collector_name, 'Collector'),
    p_bank_account_id::TEXT, COALESCE(v_bank_name, 'Bank Account'),
    p_uid, p_notes, p_timestamp
  );

  RETURN QUERY SELECT TRUE, v_tx_id, v_new_cash;
END;
$$;


ALTER FUNCTION "public"."deposit_collector_cash_tx"("p_collector_id" "text", "p_bank_account_id" "uuid", "p_amount" numeric, "p_notes" "text", "p_uid" "text", "p_timestamp" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_business_health"() RETURNS TABLE("opening_capital" numeric, "total_investor_capital" numeric, "total_outstanding_loans" numeric, "total_distributions" numeric, "bank_balance" numeric, "vf_number_balance" numeric, "retailer_debt" numeric, "retailer_insta_debt" numeric, "collector_cash" numeric, "usd_exchange_egp" numeric, "current_total_assets" numeric, "adjusted_total_assets" numeric, "reconciled_profit" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_opening_capital NUMERIC;
  v_total_investor_capital NUMERIC;
  v_total_outstanding_loans NUMERIC;
  v_total_distributions NUMERIC;
  v_bank_balance NUMERIC;
  v_vf_number_balance NUMERIC;
  v_retailer_debt NUMERIC;
  v_retailer_insta_debt NUMERIC;
  v_collector_cash NUMERIC;
  v_usd_exchange_egp NUMERIC;
  v_current_total_assets NUMERIC;
BEGIN
  -- 1. Get Opening Capital (from system_config or default)
  SELECT COALESCE((value->>'openingCapital')::NUMERIC, 300000) INTO v_opening_capital FROM system_config WHERE key = 'openingCapital';
  IF v_opening_capital IS NULL THEN v_opening_capital := 300000; END IF;

  -- 2. Sums
  SELECT COALESCE(SUM(invested_amount), 0) INTO v_total_investor_capital FROM investors WHERE status = 'active';
  SELECT COALESCE(SUM(principal_amount - amount_repaid), 0) INTO v_total_outstanding_loans FROM loans;
  
  SELECT (
    COALESCE((SELECT SUM(total_profit_paid) FROM investors), 0) + 
    COALESCE((SELECT SUM(total_profit_paid) FROM partners), 0)
  ) INTO v_total_distributions;

  SELECT COALESCE(SUM(balance), 0) INTO v_bank_balance FROM bank_accounts;
  SELECT COALESCE(SUM(initial_balance + in_total_used - out_total_used), 0) INTO v_vf_number_balance FROM mobile_numbers;
  SELECT COALESCE(SUM(GREATEST(0, total_assigned - total_collected)), 0) INTO v_retailer_debt FROM retailers;
  SELECT COALESCE(SUM(GREATEST(0, insta_pay_total_assigned - insta_pay_total_collected)), 0) INTO v_retailer_insta_debt FROM retailers;
  SELECT COALESCE(SUM(cash_on_hand), 0) INTO v_collector_cash FROM collectors;

  SELECT COALESCE(usdt_balance * last_price, 0) INTO v_usd_exchange_egp FROM usd_exchange WHERE id = 1;

  v_current_total_assets := v_bank_balance + v_vf_number_balance + v_retailer_debt + v_retailer_insta_debt + v_collector_cash + v_usd_exchange_egp;

  RETURN QUERY SELECT 
    v_opening_capital,
    v_total_investor_capital,
    v_total_outstanding_loans,
    v_total_distributions,
    v_bank_balance,
    v_vf_number_balance,
    v_retailer_debt,
    v_retailer_insta_debt,
    v_collector_cash,
    v_usd_exchange_egp,
    v_current_total_assets,
    (v_current_total_assets + v_total_outstanding_loans + v_total_distributions) as adjusted_total_assets,
    (v_current_total_assets + v_total_outstanding_loans + v_total_distributions - (v_opening_capital + v_total_investor_capital)) as reconciled_profit;
END;
$$;


ALTER FUNCTION "public"."get_business_health"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_daily_performance"("p_start_date_ts" bigint, "p_end_date_ts" bigint) RETURNS TABLE("vf_net_profit" numeric, "insta_net_profit" numeric, "total_net_profit" numeric, "total_flow" numeric, "total_vf_distributed" numeric, "total_insta_distributed" numeric, "vf_spread_profit" numeric, "vf_deposit_profit" numeric, "vf_discount_cost" numeric, "vf_fee_cost" numeric, "insta_gross_profit" numeric, "insta_fee_cost" numeric, "general_expenses" numeric, "avg_buy_price" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_avg_buy_price NUMERIC;
  v_sell_egp NUMERIC := 0;
  v_sell_usdt NUMERIC := 0;
  v_vf_dist NUMERIC := 0;
  v_insta_dist NUMERIC := 0;
  v_vf_profit_entries NUMERIC := 0;
  v_insta_profit_entries NUMERIC := 0;
  v_vf_discount NUMERIC := 0;
  v_vf_fees NUMERIC := 0;
  v_insta_fees NUMERIC := 0;
  v_expenses NUMERIC := 0;
BEGIN
  -- 1. Calculate Average Buy Price for the period (or fallback to latest before period)
  SELECT COALESCE(SUM(amount) / NULLIF(SUM(usdt_quantity), 0), 53.52) INTO v_avg_buy_price 
  FROM financial_ledger 
  WHERE type = 'BUY_USDT' AND timestamp >= p_start_date_ts AND timestamp <= p_end_date_ts;

  IF v_avg_buy_price IS NULL THEN
    SELECT COALESCE(amount / NULLIF(usdt_quantity, 0), 53.52) INTO v_avg_buy_price
    FROM financial_ledger
    WHERE type = 'BUY_USDT' AND timestamp < p_start_date_ts
    ORDER BY timestamp DESC LIMIT 1;
  END IF;
  
  IF v_avg_buy_price IS NULL THEN v_avg_buy_price := 53.52; END IF;

  -- 2. Aggregate Ledger Entries
  SELECT 
    COALESCE(SUM(CASE WHEN type = 'SELL_USDT' THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN type = 'SELL_USDT' THEN usdt_quantity ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN type = 'DISTRIBUTE_VFCASH' THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN type = 'DISTRIBUTE_INSTAPAY' THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN type = 'VFCASH_RETAIL_PROFIT' THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN type = 'INSTAPAY_DIST_PROFIT' THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN type IN ('INTERNAL_VF_TRANSFER_FEE', 'EXPENSE_VFCASH_FEE') THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN type = 'EXPENSE_INSTAPAY_FEE' THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN type = 'EXPENSE_BANK' THEN amount ELSE 0 END), 0)
  INTO 
    v_sell_egp, v_sell_usdt, v_vf_dist, v_insta_dist, v_vf_profit_entries, v_insta_profit_entries, v_vf_fees, v_insta_fees, v_expenses
  FROM financial_ledger
  WHERE timestamp >= p_start_date_ts AND timestamp <= p_end_date_ts;

  -- Return results
  RETURN QUERY SELECT
    (v_sell_egp - (v_sell_usdt * v_avg_buy_price) + v_vf_profit_entries - v_vf_fees) as vf_net_profit,
    (v_insta_profit_entries - v_insta_fees) as insta_net_profit,
    (v_sell_egp - (v_sell_usdt * v_avg_buy_price) + v_vf_profit_entries - v_vf_fees + v_insta_profit_entries - v_insta_fees - v_expenses) as total_net_profit,
    (v_vf_dist + v_insta_dist) as total_flow,
    v_vf_dist,
    v_insta_dist,
    (v_sell_egp - (v_sell_usdt * v_avg_buy_price)) as vf_spread_profit,
    v_vf_profit_entries as vf_deposit_profit,
    0::NUMERIC as vf_discount_cost,
    v_vf_fees,
    v_insta_profit_entries as insta_gross_profit,
    v_insta_fees,
    v_expenses,
    v_avg_buy_price;
END;
$$;


ALTER FUNCTION "public"."get_daily_performance"("p_start_date_ts" bigint, "p_end_date_ts" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_firebase_uid"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT firebase_uid FROM public.users 
  WHERE firebase_uid = auth.uid()::text OR id = auth.uid()
  LIMIT 1;
$$;


ALTER FUNCTION "public"."get_my_firebase_uid"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_user_info"() RETURNS TABLE("role" "text", "firebase_uid" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT role, firebase_uid FROM public.users 
  WHERE firebase_uid = auth.uid()::text OR id = auth.uid()
  LIMIT 1;
$$;


ALTER FUNCTION "public"."get_my_user_info"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_role"("target_roles" "text"[]) RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users 
    WHERE (firebase_uid = auth.uid()::text OR id = auth.uid())
      AND role = ANY(target_roles)
  );
$$;


ALTER FUNCTION "public"."has_role"("target_roles" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_mobile_number_usage"("p_number_id" "uuid", "p_amount_delta" numeric, "p_direction" "text", "p_timestamp_ms" bigint, "p_require_sufficient_balance" boolean DEFAULT false, "p_clamp_at_zero" boolean DEFAULT false) RETURNS TABLE("committed" boolean, "new_balance" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_current_rec RECORD;
  v_new_total NUMERIC;
  v_new_daily NUMERIC;
  v_new_monthly NUMERIC;
  v_today_start_ms BIGINT;
  v_month_start_ms BIGINT;
  v_prefix TEXT;
  v_current_balance NUMERIC;
BEGIN
  -- 1. Lock the row
  SELECT * INTO v_current_rec FROM mobile_numbers WHERE id = p_number_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 0::NUMERIC;
    RETURN;
  END IF;

  -- Normalize direction and validate
  IF p_direction IN ('in', 'incoming') THEN
    v_prefix := 'in';
  ELSIF p_direction IN ('out', 'outgoing') THEN
    v_prefix := 'out';
  ELSE
    RAISE EXCEPTION 'Invalid direction: %. Expected ''in'' or ''out''.', p_direction;
  END IF;

  v_current_balance := v_current_rec.initial_balance + v_current_rec.in_total_used - v_current_rec.out_total_used;

  -- 2. Sufficient balance check
  IF p_require_sufficient_balance AND v_prefix = 'out' AND p_amount_delta > 0 THEN
    IF p_amount_delta > (v_current_balance + 0.01) THEN
      RETURN QUERY SELECT FALSE, v_current_balance;
      RETURN;
    END IF;
  END IF;

  -- 3. Calculate next values and check if they would go negative (if not clamping)
  v_today_start_ms := (EXTRACT(EPOCH FROM (CURRENT_DATE AT TIME ZONE 'UTC')) * 1000)::BIGINT;
  v_month_start_ms := (EXTRACT(EPOCH FROM (DATE_TRUNC('month', CURRENT_DATE) AT TIME ZONE 'UTC')) * 1000)::BIGINT;

  IF v_prefix = 'in' THEN
    v_new_total := v_current_rec.in_total_used + p_amount_delta;
    v_new_daily := CASE WHEN p_timestamp_ms >= v_today_start_ms THEN v_current_rec.in_daily_used + p_amount_delta ELSE v_current_rec.in_daily_used END;
    v_new_monthly := CASE WHEN p_timestamp_ms >= v_month_start_ms THEN v_current_rec.in_monthly_used + p_amount_delta ELSE v_current_rec.in_monthly_used END;
  ELSE
    v_new_total := v_current_rec.out_total_used + p_amount_delta;
    v_new_daily := CASE WHEN p_timestamp_ms >= v_today_start_ms THEN v_current_rec.out_daily_used + p_amount_delta ELSE v_current_rec.out_daily_used END;
    v_new_monthly := CASE WHEN p_timestamp_ms >= v_month_start_ms THEN v_current_rec.out_monthly_used + p_amount_delta ELSE v_current_rec.out_monthly_used END;
  END IF;

  -- Underflow checks
  IF NOT p_clamp_at_zero AND p_amount_delta < 0 THEN
    IF v_new_total < -0.01 OR 
       (p_timestamp_ms >= v_today_start_ms AND v_new_daily < -0.01) OR 
       (p_timestamp_ms >= v_month_start_ms AND v_new_monthly < -0.01) THEN
      RETURN QUERY SELECT FALSE, v_current_balance;
      RETURN;
    END IF;
  END IF;

  -- Apply clamping
  IF p_clamp_at_zero THEN
    v_new_total := GREATEST(0, v_new_total);
    v_new_daily := GREATEST(0, v_new_daily);
    v_new_monthly := GREATEST(0, v_new_monthly);
  END IF;

  -- 4. Update the row
  IF v_prefix = 'in' THEN
    UPDATE mobile_numbers SET
      in_total_used = v_new_total,
      in_daily_used = v_new_daily,
      in_monthly_used = v_new_monthly,
      last_updated_at = now()
    WHERE id = p_number_id;
  ELSE
    UPDATE mobile_numbers SET
      out_total_used = v_new_total,
      out_daily_used = v_new_daily,
      out_monthly_used = v_new_monthly,
      last_updated_at = now()
    WHERE id = p_number_id;
  END IF;

  -- 6. Return new state
  SELECT initial_balance + in_total_used - out_total_used INTO v_current_balance FROM mobile_numbers WHERE id = p_number_id;
  RETURN QUERY SELECT TRUE, v_current_balance;
END;
$$;


ALTER FUNCTION "public"."increment_mobile_number_usage"("p_number_id" "uuid", "p_amount_delta" numeric, "p_direction" "text", "p_timestamp_ms" bigint, "p_require_sufficient_balance" boolean, "p_clamp_at_zero" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users 
    WHERE (firebase_uid = auth.uid()::text OR id = auth.uid())
      AND role = 'ADMIN'
  );
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."issue_loan"("p_source_type" "text", "p_source_id" "text", "p_borrower_name" "text", "p_borrower_phone" "text", "p_amount" numeric, "p_notes" "text", "p_created_by_uid" "text") RETURNS TABLE("success" boolean, "loan_id" "uuid", "tx_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_loan_id UUID := gen_random_uuid();
  v_tx_id UUID := gen_random_uuid();
  v_source_label TEXT;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
BEGIN
  -- 1. Validate and update source balance
  IF p_source_type = 'bank' THEN
    UPDATE bank_accounts 
    SET balance = balance - p_amount,
        last_updated_at = now()
    WHERE id = p_source_id::UUID AND balance >= p_amount
    RETURNING bank_name INTO v_source_label;
    
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Insufficient bank balance or bank not found.';
    END IF;
  ELSIF p_source_type = 'collector' THEN
    UPDATE collectors
    SET cash_on_hand = cash_on_hand - p_amount,
        last_updated_at = now()
    WHERE id = p_source_id AND cash_on_hand >= p_amount
    RETURNING name INTO v_source_label;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Insufficient collector cash or collector not found.';
    END IF;
  ELSE
    RAISE EXCEPTION 'Invalid source type: %', p_source_type;
  END IF;

  -- 2. Insert Loan Record
  INSERT INTO loans (
    id, borrower_name, borrower_phone, principal_amount, amount_repaid,
    source_type, source_id, source_label, status, issued_at, last_updated_at,
    notes, created_by_uid
  ) VALUES (
    v_loan_id, p_borrower_name, p_borrower_phone, p_amount, 0,
    p_source_type, p_source_id, v_source_label, 'active', v_now_ts, v_now_ts,
    p_notes, p_created_by_uid
  );

  -- 3. Insert Ledger Entry
  INSERT INTO financial_ledger (
    id, type, amount, from_id, from_label, to_label, notes, created_by_uid, timestamp
  ) VALUES (
    v_tx_id, 'LOAN_ISSUED', p_amount, p_source_id, v_source_label, p_borrower_name,
    'Loan issued to ' || p_borrower_name || COALESCE(': ' || p_notes, ''),
    p_created_by_uid, v_now_ts
  );

  RETURN QUERY SELECT TRUE, v_loan_id, v_tx_id;
END;
$$;


ALTER FUNCTION "public"."issue_loan"("p_source_type" "text", "p_source_id" "text", "p_borrower_name" "text", "p_borrower_phone" "text", "p_amount" numeric, "p_notes" "text", "p_created_by_uid" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_bybit_order_sync"("p_order_id" "text", "p_side" integer, "p_amount" numeric, "p_price" numeric, "p_quantity" numeric, "p_currency" "text", "p_token" "text", "p_timestamp_ms" bigint, "p_payment_method" "text", "p_chat_history" "text", "p_matched_phone" "text", "p_matched_phone_id" "uuid", "p_from_id" "text", "p_from_label" "text", "p_to_id" "text", "p_to_label" "text", "p_is_vodafone_buy" boolean, "p_bank_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- 1. Insert Transaction if it doesn't exist
  INSERT INTO transactions (
    bybit_order_id, phone_number, amount, currency, timestamp, 
    status, payment_method, side, chat_history, price, quantity, token
  )
  VALUES (
    p_order_id, p_matched_phone, p_amount, p_currency, to_timestamp(p_timestamp_ms / 1000.0),
    'completed', p_payment_method, p_side, p_chat_history, p_price, p_quantity, p_token
  )
  ON CONFLICT (bybit_order_id) DO NOTHING;

  -- 2. Insert Ledger Entry and perform side effects only if ledger doesn't exist for this order
  IF NOT EXISTS (SELECT 1 FROM financial_ledger WHERE bybit_order_id = p_order_id) THEN
    INSERT INTO financial_ledger (
      type, amount, usdt_price, usdt_quantity, from_id, from_label, 
      to_id, to_label, bybit_order_id, created_by_uid, timestamp
    )
    VALUES (
      CASE WHEN p_side = 0 THEN 'BUY_USDT' ELSE 'SELL_USDT' END,
      p_amount, p_price, p_quantity, p_from_id, p_from_label,
      p_to_id, p_to_label, p_order_id, 'server_sync', p_timestamp_ms
    );

    -- 3. Side-specific logic
    IF p_side = 0 THEN -- BUY
      IF p_is_vodafone_buy AND p_matched_phone_id IS NOT NULL THEN
        PERFORM apply_mobile_number_usage_delta(p_matched_phone_id, p_amount, 'out', p_timestamp_ms);
      ELSIF NOT p_is_vodafone_buy AND p_bank_id IS NOT NULL THEN
        -- Outgoing from Bank with sufficient balance check
        UPDATE bank_accounts 
        SET balance = balance - p_amount, 
            last_updated_at = now() 
        WHERE id = p_bank_id AND balance >= p_amount;
        
        IF NOT FOUND THEN
          RAISE EXCEPTION 'Insufficient bank balance for bank_id % (Order: %)', p_bank_id, p_order_id;
        END IF;
      END IF;
      UPDATE usd_exchange SET usdt_balance = usdt_balance + p_quantity, last_price = p_price, last_updated_at = now() WHERE id = 1;
    ELSIF p_side = 1 THEN -- SELL
      IF p_matched_phone_id IS NOT NULL THEN
        PERFORM apply_mobile_number_usage_delta(p_matched_phone_id, p_amount, 'in', p_timestamp_ms);
      END IF;
      UPDATE usd_exchange SET usdt_balance = usdt_balance - p_quantity, last_price = p_price, last_updated_at = now() WHERE id = 1;
    END IF;
  END IF;
END;
$$;


ALTER FUNCTION "public"."process_bybit_order_sync"("p_order_id" "text", "p_side" integer, "p_amount" numeric, "p_price" numeric, "p_quantity" numeric, "p_currency" "text", "p_token" "text", "p_timestamp_ms" bigint, "p_payment_method" "text", "p_chat_history" "text", "p_matched_phone" "text", "p_matched_phone_id" "uuid", "p_from_id" "text", "p_from_label" "text", "p_to_id" "text", "p_to_label" "text", "p_is_vodafone_buy" boolean, "p_bank_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_expense"("p_type" "text", "p_amount" numeric, "p_target_id" "text", "p_category" "text", "p_notes" "text", "p_created_by_uid" "text") RETURNS TABLE("success" boolean, "tx_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tx_id UUID := gen_random_uuid();
  v_source_label TEXT;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
BEGIN
  -- 1. Deduct from Source
  IF p_type = 'EXPENSE_BANK' THEN
    UPDATE bank_accounts 
    SET balance = balance - p_amount,
        last_updated_at = now()
    WHERE id = p_target_id::UUID AND balance >= p_amount
    RETURNING bank_name INTO v_source_label;
    
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Insufficient bank balance or bank not found.';
    END IF;
  ELSIF p_type = 'EXPENSE_VFNUMBER' THEN
    PERFORM apply_mobile_number_usage_delta(p_target_id::UUID, p_amount, 'out', v_now_ts);
    SELECT phone_number INTO v_source_label FROM mobile_numbers WHERE id = p_target_id::UUID;
  ELSIF p_type = 'EXPENSE_COLLECTOR' THEN
    UPDATE collectors
    SET cash_on_hand = cash_on_hand - p_amount,
        last_updated_at = now()
    WHERE id = p_target_id AND cash_on_hand >= p_amount
    RETURNING name INTO v_source_label;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Insufficient collector cash or collector not found.';
    END IF;
  ELSE
    RAISE EXCEPTION 'Invalid expense type: %', p_type;
  END IF;

  -- 2. Insert Ledger Entry
  INSERT INTO financial_ledger (
    id, type, amount, from_id, from_label, to_label, category, notes, created_by_uid, timestamp
  ) VALUES (
    v_tx_id, p_type, p_amount, p_target_id, v_source_label, 'System Expense', p_category,
    p_notes, p_created_by_uid, v_now_ts
  );

  RETURN QUERY SELECT TRUE, v_tx_id;
END;
$$;


ALTER FUNCTION "public"."record_expense"("p_type" "text", "p_amount" numeric, "p_target_id" "text", "p_category" "text", "p_notes" "text", "p_created_by_uid" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_investor_capital"("p_name" "text", "p_phone" "text", "p_invested_amount" numeric, "p_initial_business_capital" numeric, "p_profit_share_percent" numeric, "p_investment_date" bigint, "p_period_days" integer, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") RETURNS TABLE("success" boolean, "investor_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_investor_id UUID := gen_random_uuid();
  v_tx_id UUID := gen_random_uuid();
  v_bank_name TEXT;
  v_prior_capital NUMERIC := 0;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  v_date_key TEXT := to_char(to_timestamp(COALESCE(p_investment_date, v_now_ts) / 1000.0), 'YYYY-MM-DD');
BEGIN
  -- 1. Calculate prior capital
  SELECT COALESCE(SUM(invested_amount), 0) INTO v_prior_capital FROM investors WHERE status = 'active';

  -- 2. Update Bank Balance
  UPDATE bank_accounts 
  SET balance = balance + p_invested_amount,
      last_updated_at = now()
  WHERE id = p_bank_account_id
  RETURNING bank_name INTO v_bank_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bank account not found.';
  END IF;

  -- 3. Insert Investor
  INSERT INTO investors (
    id, name, phone, invested_amount, half_invested_amount, initial_business_capital,
    cumulative_capital_before, half_cumulative_capital, profit_share_percent,
    investment_date, period_days, status, total_profit_paid, notes,
    created_by_uid, created_at, capital_history
  ) VALUES (
    v_investor_id, p_name, p_phone, p_invested_amount, p_invested_amount / 2.0, p_initial_business_capital,
    p_initial_business_capital + v_prior_capital, (p_initial_business_capital + v_prior_capital) / 2.0,
    p_profit_share_percent, p_investment_date, COALESCE(p_period_days, 30), 'active', 0, p_notes,
    p_created_by_uid, v_now_ts, jsonb_build_object(v_date_key, p_invested_amount)
  );

  -- 4. Insert Ledger Entry
  INSERT INTO financial_ledger (
    id, type, amount, to_id, to_label, from_label, notes, created_by_uid, timestamp
  ) VALUES (
    v_tx_id, 'INVESTOR_CAPITAL_IN', p_invested_amount, p_bank_account_id::TEXT, v_bank_name, p_name,
    'Investor capital deposit from ' || p_name,
    p_created_by_uid, v_now_ts
  );

  RETURN QUERY SELECT TRUE, v_investor_id;
END;
$$;


ALTER FUNCTION "public"."record_investor_capital"("p_name" "text", "p_phone" "text", "p_invested_amount" numeric, "p_initial_business_capital" numeric, "p_profit_share_percent" numeric, "p_investment_date" bigint, "p_period_days" integer, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_investor_payout"("p_investor_id" "uuid", "p_amount" numeric, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") RETURNS TABLE("success" boolean, "tx_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tx_id UUID := gen_random_uuid();
  v_bank_name TEXT;
  v_investor_name TEXT;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
BEGIN
  -- 1. Update Bank Balance
  UPDATE bank_accounts 
  SET balance = balance - p_amount,
      last_updated_at = now()
  WHERE id = p_bank_account_id AND balance >= p_amount
  RETURNING bank_name INTO v_bank_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Insufficient bank balance or bank not found.';
  END IF;

  -- 2. Update Investor
  UPDATE investors SET
    total_profit_paid = total_profit_paid + p_amount,
    last_paid_at = v_now_ts
  WHERE id = p_investor_id
  RETURNING name INTO v_investor_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Investor not found.';
  END IF;

  -- 3. Insert Ledger Entry
  INSERT INTO financial_ledger (
    id, type, amount, from_id, from_label, to_label, notes, created_by_uid, timestamp
  ) VALUES (
    v_tx_id, 'INVESTOR_PROFIT_PAID', p_amount, p_bank_account_id::TEXT, v_bank_name, v_investor_name,
    COALESCE(p_notes, 'Investor Profit Payout'),
    p_created_by_uid, v_now_ts
  );

  RETURN QUERY SELECT TRUE, v_tx_id;
END;
$$;


ALTER FUNCTION "public"."record_investor_payout"("p_investor_id" "uuid", "p_amount" numeric, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_loan_repayment"("p_loan_id" "uuid", "p_amount" numeric, "p_created_by_uid" "text") RETURNS TABLE("success" boolean, "tx_id" "uuid", "new_status" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tx_id UUID := gen_random_uuid();
  v_loan RECORD;
  v_new_amount_repaid NUMERIC;
  v_new_status TEXT;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
BEGIN
  -- 1. Get Loan and Lock it
  SELECT * INTO v_loan FROM loans WHERE id = p_loan_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Loan not found.';
  END IF;

  IF v_loan.status = 'fully_repaid' THEN
    RAISE EXCEPTION 'Loan is already fully repaid.';
  END IF;

  v_new_amount_repaid := v_loan.amount_repaid + p_amount;
  IF v_new_amount_repaid > (v_loan.principal_amount + 0.01) THEN
    RAISE EXCEPTION 'Repayment exceeds outstanding balance.';
  END IF;

  IF v_new_amount_repaid >= (v_loan.principal_amount - 0.01) THEN
    v_new_status := 'fully_repaid';
  ELSE
    v_new_status := 'active';
  END IF;

  -- 2. Update Loan
  UPDATE loans SET
    amount_repaid = v_new_amount_repaid,
    status = v_new_status,
    repaid_at = CASE WHEN v_new_status = 'fully_repaid' THEN v_now_ts ELSE repaid_at END,
    last_updated_at = v_now_ts
  WHERE id = p_loan_id;

  -- 3. Update Source Balance
  IF v_loan.source_type = 'bank' THEN
    UPDATE bank_accounts SET
      balance = balance + p_amount,
      last_updated_at = now()
    WHERE id = v_loan.source_id::UUID;
  ELSIF v_loan.source_type = 'collector' THEN
    UPDATE collectors SET
      cash_on_hand = cash_on_hand + p_amount,
      last_updated_at = now()
    WHERE id = v_loan.source_id;
  END IF;

  -- 4. Insert Ledger Entry
  INSERT INTO financial_ledger (
    id, type, amount, from_label, to_id, to_label, notes, created_by_uid, timestamp
  ) VALUES (
    v_tx_id, 'LOAN_REPAYMENT', p_amount, v_loan.borrower_name, v_loan.source_id, v_loan.source_label,
    'Repayment from ' || v_loan.borrower_name || CASE WHEN v_new_status = 'fully_repaid' THEN ' (Fully Repaid)' ELSE '' END,
    p_created_by_uid, v_now_ts
  );

  RETURN QUERY SELECT TRUE, v_tx_id, v_new_status;
END;
$$;


ALTER FUNCTION "public"."record_loan_repayment"("p_loan_id" "uuid", "p_amount" numeric, "p_created_by_uid" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_partner_payout"("p_partner_id" "uuid", "p_amount" numeric, "p_payment_source_type" "text", "p_payment_source_id" "text", "p_notes" "text", "p_created_by_uid" "text") RETURNS TABLE("success" boolean, "tx_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tx_id UUID := gen_random_uuid();
  v_source_label TEXT;
  v_partner_name TEXT;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  v_type TEXT;
BEGIN
  -- 1. Update Partner Record
  UPDATE partners SET
    total_profit_paid = total_profit_paid + p_amount,
    last_paid_at = v_now_ts,
    updated_at = v_now_ts
  WHERE id = p_partner_id
  RETURNING name INTO v_partner_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Partner not found.';
  END IF;

  -- 2. Deduct from Source
  IF p_payment_source_type = 'bank' THEN
    UPDATE bank_accounts 
    SET balance = balance - p_amount,
        last_updated_at = now()
    WHERE id = p_payment_source_id::UUID AND balance >= p_amount
    RETURNING bank_name INTO v_source_label;
    
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Insufficient bank balance or bank not found.';
    END IF;
    v_type := 'PARTNER_PROFIT_PAID_BANK';
  ELSIF p_payment_source_type = 'vf' THEN
    -- Use the atomic usage delta function
    PERFORM apply_mobile_number_usage_delta(p_payment_source_id::UUID, p_amount, 'out', v_now_ts);
    
    SELECT phone_number INTO v_source_label FROM mobile_numbers WHERE id = p_payment_source_id::UUID;
    v_type := 'PARTNER_PROFIT_PAID_VF';
  ELSE
    RAISE EXCEPTION 'Invalid payment source type: %', p_payment_source_type;
  END IF;

  -- 3. Insert Ledger Entry
  INSERT INTO financial_ledger (
    id, type, amount, from_id, from_label, to_label, notes, created_by_uid, timestamp
  ) VALUES (
    v_tx_id, v_type, p_amount, p_payment_source_id, v_source_label, v_partner_name,
    COALESCE(p_notes, 'Partner Profit Payout'),
    p_created_by_uid, v_now_ts
  );

  RETURN QUERY SELECT TRUE, v_tx_id;
END;
$$;


ALTER FUNCTION "public"."record_partner_payout"("p_partner_id" "uuid", "p_amount" numeric, "p_payment_source_type" "text", "p_payment_source_id" "text", "p_notes" "text", "p_created_by_uid" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."release_sync_lock"("p_owner_id" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  DELETE FROM sync_locks WHERE id = 1 AND owner_id = p_owner_id;
END;
$$;


ALTER FUNCTION "public"."release_sync_lock"("p_owner_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_daily_limits"() RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  UPDATE mobile_numbers 
  SET in_daily_used = 0, 
      out_daily_used = 0
  WHERE true;
$$;


ALTER FUNCTION "public"."reset_daily_limits"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_retailer_pending_debt"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.pending_debt := GREATEST(0, NEW.total_assigned - NEW.total_collected);
  NEW.insta_pay_pending_debt := GREATEST(0, NEW.insta_pay_total_assigned - NEW.insta_pay_total_collected);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_retailer_pending_debt"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."upsert_daily_flow_summary"("p_date_key" "text", "p_vf_delta" numeric, "p_insta_delta" numeric) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO daily_flow_summary (date_key, vf_amount, insta_amount)
  VALUES (p_date_key, p_vf_delta, p_insta_delta)
  ON CONFLICT (date_key) DO UPDATE SET
    vf_amount = daily_flow_summary.vf_amount + EXCLUDED.vf_amount,
    insta_amount = daily_flow_summary.insta_amount + EXCLUDED.insta_amount;
END;
$$;


ALTER FUNCTION "public"."upsert_daily_flow_summary"("p_date_key" "text", "p_vf_delta" numeric, "p_insta_delta" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."withdraw_investor_capital"("p_investor_id" "uuid", "p_amount" numeric, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") RETURNS TABLE("success" boolean, "tx_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tx_id UUID := gen_random_uuid();
  v_bank_name TEXT;
  v_investor RECORD;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  v_date_key TEXT := to_char(to_timestamp(v_now_ts / 1000.0), 'YYYY-MM-DD');
BEGIN
  -- 1. Get Investor and Lock it
  SELECT * INTO v_investor FROM investors WHERE id = p_investor_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Investor not found.';
  END IF;

  IF p_amount > v_investor.invested_amount THEN
    RAISE EXCEPTION 'Withdrawal amount exceeds invested amount.';
  END IF;

  -- 2. Update Bank Balance
  UPDATE bank_accounts 
  SET balance = balance - p_amount,
      last_updated_at = now()
  WHERE id = p_bank_account_id AND balance >= p_amount
  RETURNING bank_name INTO v_bank_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Insufficient bank balance or bank not found.';
  END IF;

  -- 3. Update Investor
  UPDATE investors SET
    invested_amount = invested_amount - p_amount,
    half_invested_amount = (invested_amount - p_amount) / 2.0,
    status = CASE WHEN (invested_amount - p_amount) <= 0 THEN 'withdrawn' ELSE status END,
    capital_history = capital_history || jsonb_build_object(v_date_key, invested_amount - p_amount)
  WHERE id = p_investor_id;

  -- 4. Insert Ledger Entry
  INSERT INTO financial_ledger (
    id, type, amount, from_id, from_label, to_label, notes, created_by_uid, timestamp
  ) VALUES (
    v_tx_id, 'INVESTOR_CAPITAL_OUT', p_amount, p_bank_account_id::TEXT, v_bank_name, v_investor.name,
    COALESCE(p_notes, 'Capital Withdrawal'),
    p_created_by_uid, v_now_ts
  );

  RETURN QUERY SELECT TRUE, v_tx_id;
END;
$$;


ALTER FUNCTION "public"."withdraw_investor_capital"("p_investor_id" "uuid", "p_amount" numeric, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."bank_accounts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_holder" "text",
    "account_number" "text",
    "balance" numeric(15,4) DEFAULT 0,
    "bank_name" "text",
    "is_default_for_buy" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "last_updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."bank_accounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."collectors" (
    "id" "text" NOT NULL,
    "uid" "text",
    "name" "text",
    "phone" "text",
    "email" "text",
    "cash_on_hand" numeric(15,4) DEFAULT 0,
    "cash_limit" numeric(15,4) DEFAULT 50000,
    "total_collected" numeric(15,4) DEFAULT 0,
    "total_deposited" numeric(15,4) DEFAULT 0,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "last_updated_at" timestamp with time zone DEFAULT "now"(),
    "supabase_uid" "uuid"
);


ALTER TABLE "public"."collectors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_flow_summary" (
    "date_key" "text" NOT NULL,
    "vf_amount" numeric(15,4) DEFAULT 0,
    "insta_amount" numeric(15,4) DEFAULT 0
);


ALTER TABLE "public"."daily_flow_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."daily_stats" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "year" integer,
    "month" integer,
    "day" integer,
    "collector_id" "text",
    "collections" integer DEFAULT 0,
    "expenses" integer DEFAULT 0,
    "profit" numeric DEFAULT 0,
    "total_collections" numeric DEFAULT 0,
    "total_expenses" integer DEFAULT 0,
    "total_profit" numeric DEFAULT 0
);


ALTER TABLE "public"."daily_stats" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."financial_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "type" "text" NOT NULL,
    "amount" numeric(15,4),
    "from_id" "text",
    "from_label" "text",
    "to_id" "text",
    "to_label" "text",
    "created_by_uid" "text",
    "notes" "text",
    "timestamp" bigint,
    "bybit_order_id" "text",
    "related_ledger_id" "uuid",
    "generated_transaction_id" "uuid",
    "transferred_amount" numeric,
    "fee_amount" numeric,
    "fee_rate_per_1000" numeric,
    "collected_portion" numeric,
    "credit_portion" numeric,
    "usdt_price" numeric,
    "usdt_quantity" numeric,
    "profit_per_1000" numeric,
    "category" "text",
    "payment_method" "text"
);


ALTER TABLE "public"."financial_ledger" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."investor_profit_snapshots" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "investor_id" "uuid",
    "date_key" "text" NOT NULL,
    "hurdle" numeric(15,4),
    "preceding_capital" numeric(15,4),
    "excess" numeric(15,4),
    "vf_excess" numeric(15,4),
    "insta_excess" numeric(15,4),
    "vf_net_per_1000" numeric(15,4),
    "insta_net_per_1000" numeric(15,4),
    "vf_investor_profit" numeric(15,4),
    "insta_investor_profit" numeric(15,4),
    "investor_profit" numeric(15,4),
    "total_flow" numeric(15,4),
    "vf_flow" numeric(15,4),
    "insta_flow" numeric(15,4),
    "profit_share_percent" numeric(15,4),
    "opening_capital" numeric(15,4),
    "total_loans_outstanding" numeric(15,4),
    "current_total_assets" numeric(15,4),
    "reconciled_profit" numeric(15,4),
    "current_bank_balance" numeric(15,4),
    "usd_exchange_egp" numeric(15,4),
    "retailer_vf_debt" numeric(15,4),
    "collector_cash" numeric(15,4),
    "retailer_insta_debt" numeric(15,4),
    "global_avg_buy_price" numeric(15,4),
    "total_net_profit" numeric(15,4),
    "working_days" integer DEFAULT 1,
    "calculation_version" numeric,
    "is_paid" boolean DEFAULT false,
    "paid_at" bigint,
    "paid_by_uid" "text",
    "calculated_at" bigint
);


ALTER TABLE "public"."investor_profit_snapshots" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."investors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text",
    "phone" "text",
    "invested_amount" numeric(15,4),
    "half_invested_amount" numeric(15,4),
    "initial_business_capital" numeric(15,4),
    "cumulative_capital_before" numeric(15,4),
    "half_cumulative_capital" numeric(15,4),
    "profit_share_percent" numeric,
    "investment_date" bigint,
    "period_days" integer,
    "status" "text",
    "total_profit_paid" numeric(15,4) DEFAULT 0,
    "capital_history" "jsonb" DEFAULT '{}'::"jsonb",
    "notes" "text",
    "created_by_uid" "text",
    "created_at" bigint,
    "last_paid_at" bigint
);


ALTER TABLE "public"."investors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."loans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "borrower_name" "text",
    "borrower_phone" "text",
    "principal_amount" numeric(15,4),
    "amount_repaid" numeric(15,4) DEFAULT 0,
    "source_type" "text",
    "source_id" "text",
    "source_label" "text",
    "status" "text",
    "issued_at" bigint,
    "repaid_at" bigint,
    "last_updated_at" bigint,
    "notes" "text",
    "created_by_uid" "text"
);


ALTER TABLE "public"."loans" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."mobile_numbers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "phone_number" "text",
    "initial_balance" numeric(15,4) DEFAULT 0,
    "in_total_used" numeric(15,4) DEFAULT 0,
    "out_total_used" numeric(15,4) DEFAULT 0,
    "in_daily_used" numeric(15,4) DEFAULT 0,
    "in_daily_limit" numeric(15,4) DEFAULT 100000,
    "out_daily_used" numeric(15,4) DEFAULT 0,
    "out_daily_limit" numeric(15,4) DEFAULT 100000,
    "in_monthly_used" numeric(15,4) DEFAULT 0,
    "in_monthly_limit" numeric(15,4) DEFAULT 1000000,
    "out_monthly_used" numeric(15,4) DEFAULT 0,
    "out_monthly_limit" numeric(15,4) DEFAULT 1000000,
    "is_default" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "last_updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."mobile_numbers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."partner_profit_snapshots" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "partner_id" "uuid",
    "date_key" "text" NOT NULL,
    "total_net_profit" numeric(15,4),
    "allocation_ratio" numeric(15,4),
    "reconciled_pool" numeric(15,4),
    "total_investor_profit_deducted" numeric(15,4),
    "remaining_for_partners" numeric(15,4),
    "partner_profit" numeric(15,4),
    "share_percent" numeric(15,4),
    "vf_spread_profit" numeric(15,4),
    "vf_deposit_profit" numeric(15,4),
    "vf_discount_cost" numeric(15,4),
    "vf_fee_cost" numeric(15,4),
    "vf_net_profit" numeric(15,4),
    "vf_net_per_1000" numeric(15,4),
    "insta_gross_profit" numeric(15,4),
    "insta_fee_cost" numeric(15,4),
    "insta_net_profit" numeric(15,4),
    "insta_net_per_1000" numeric(15,4),
    "general_expenses" numeric(15,4),
    "global_avg_buy_price" numeric(15,4),
    "vf_daily_flow" numeric(15,4),
    "insta_daily_flow" numeric(15,4),
    "total_daily_flow" numeric(15,4),
    "total_vf_distributed" numeric(15,4),
    "total_insta_distributed" numeric(15,4),
    "working_days" integer DEFAULT 1,
    "calculation_version" numeric,
    "is_paid" boolean DEFAULT false,
    "paid_at" bigint,
    "paid_by_uid" "text",
    "paid_from_type" "text",
    "paid_from_id" "text",
    "calculated_at" bigint
);


ALTER TABLE "public"."partner_profit_snapshots" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."partners" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text",
    "share_percent" numeric,
    "status" "text",
    "total_profit_paid" numeric(15,4) DEFAULT 0,
    "created_at" bigint,
    "updated_at" bigint,
    "last_paid_at" bigint
);


ALTER TABLE "public"."partners" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."retailers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text",
    "phone" "text",
    "assigned_collector_id" "text",
    "discount_per_1000" numeric,
    "insta_pay_profit_per_1000" numeric,
    "total_assigned" numeric(15,4) DEFAULT 0,
    "total_collected" numeric(15,4) DEFAULT 0,
    "insta_pay_total_assigned" numeric(15,4) DEFAULT 0,
    "insta_pay_total_collected" numeric(15,4) DEFAULT 0,
    "insta_pay_pending_debt" numeric(15,4) DEFAULT 0,
    "pending_debt" numeric(15,4) DEFAULT 0,
    "credit" numeric(15,4) DEFAULT 0,
    "area" "text",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "last_updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."retailers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rollback_points" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "label" "text",
    "note" "text",
    "created_by_uid" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rollback_points" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rollback_snapshots" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "point_id" "uuid",
    "table_name" "text" NOT NULL,
    "row_count" integer DEFAULT 0,
    "rows" "jsonb" NOT NULL
);


ALTER TABLE "public"."rollback_snapshots" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sync_locks" (
    "id" integer DEFAULT 1 NOT NULL,
    "owner_id" "text" NOT NULL,
    "acquired_at" timestamp with time zone DEFAULT "now"(),
    "expires_at" timestamp with time zone NOT NULL,
    CONSTRAINT "single_row_lock" CHECK (("id" = 1))
);


ALTER TABLE "public"."sync_locks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sync_state" (
    "id" integer DEFAULT 1 NOT NULL,
    "last_synced_order_ts" bigint DEFAULT 0,
    "last_sync_time" bigint,
    "last_server_sync_status" "text",
    CONSTRAINT "single_row" CHECK (("id" = 1))
);


ALTER TABLE "public"."sync_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."system_config" (
    "key" "text" NOT NULL,
    "value" "jsonb"
);


ALTER TABLE "public"."system_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."system_profit_snapshots" (
    "date_key" "text" NOT NULL,
    "vf_net_profit" numeric(15,4),
    "insta_net_profit" numeric(15,4),
    "total_net_profit" numeric(15,4),
    "vf_net_per_1000" numeric(15,4),
    "insta_net_per_1000" numeric(15,4),
    "total_flow" numeric(15,4),
    "total_vf_distributed" numeric(15,4),
    "total_insta_distributed" numeric(15,4),
    "daily_avg_buy_price" numeric(15,4),
    "global_avg_buy_price" numeric(15,4),
    "vf_spread_profit" numeric(15,4),
    "vf_deposit_profit" numeric(15,4),
    "vf_discount_cost" numeric(15,4),
    "vf_fee_cost" numeric(15,4),
    "insta_gross_profit" numeric(15,4),
    "insta_fee_cost" numeric(15,4),
    "general_expenses" numeric(15,4),
    "total_sell_usdt" numeric(15,4),
    "total_sell_egp" numeric(15,4),
    "opening_capital" numeric(15,4),
    "effective_starting_capital" numeric(15,4),
    "total_outstanding_loans" numeric(15,4),
    "current_total_assets" numeric(15,4),
    "bank_balance" numeric(15,4),
    "vf_number_balance" numeric(15,4),
    "retailer_debt" numeric(15,4),
    "retailer_insta_debt" numeric(15,4),
    "collector_cash" numeric(15,4),
    "usd_exchange_egp" numeric(15,4),
    "adjusted_total_assets" numeric(15,4),
    "reconciled_profit" numeric(15,4),
    "working_days" integer DEFAULT 1,
    "calculation_version" numeric,
    "calculated_at" bigint,
    "sell_entries_count" integer,
    "buy_entries_range_count" integer
);


ALTER TABLE "public"."system_profit_snapshots" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."transactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "phone_number" "text",
    "amount" numeric(15,4),
    "currency" "text" DEFAULT 'EGP'::"text",
    "timestamp" timestamp with time zone DEFAULT "now"(),
    "bybit_order_id" "text",
    "status" "text",
    "payment_method" "text",
    "side" smallint,
    "chat_history" "text",
    "price" numeric,
    "quantity" numeric,
    "token" "text",
    "related_ledger_id" "uuid"
);


ALTER TABLE "public"."transactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."uid_mapping" (
    "firebase_uid" "text" NOT NULL,
    "supabase_uid" "uuid" NOT NULL
);


ALTER TABLE "public"."uid_mapping" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."usd_exchange" (
    "id" integer DEFAULT 1 NOT NULL,
    "usdt_balance" numeric(15,6) DEFAULT 0,
    "last_price" numeric,
    "last_updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "single_row" CHECK (("id" = 1))
);


ALTER TABLE "public"."usd_exchange" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "firebase_uid" "text",
    "email" "text" NOT NULL,
    "name" "text",
    "role" "text",
    "is_active" boolean DEFAULT true,
    "retailer_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "users_role_check" CHECK (("role" = ANY (ARRAY['ADMIN'::"text", 'FINANCE'::"text", 'COLLECTOR'::"text", 'RETAILER'::"text"])))
);


ALTER TABLE "public"."users" OWNER TO "postgres";


ALTER TABLE ONLY "public"."bank_accounts"
    ADD CONSTRAINT "bank_accounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."collectors"
    ADD CONSTRAINT "collectors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."daily_flow_summary"
    ADD CONSTRAINT "daily_flow_summary_pkey" PRIMARY KEY ("date_key");



ALTER TABLE ONLY "public"."daily_stats"
    ADD CONSTRAINT "daily_stats_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."financial_ledger"
    ADD CONSTRAINT "financial_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."investor_profit_snapshots"
    ADD CONSTRAINT "investor_profit_snapshots_investor_id_date_key_key" UNIQUE ("investor_id", "date_key");



ALTER TABLE ONLY "public"."investor_profit_snapshots"
    ADD CONSTRAINT "investor_profit_snapshots_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."investors"
    ADD CONSTRAINT "investors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."loans"
    ADD CONSTRAINT "loans_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."mobile_numbers"
    ADD CONSTRAINT "mobile_numbers_phone_number_key" UNIQUE ("phone_number");



ALTER TABLE ONLY "public"."mobile_numbers"
    ADD CONSTRAINT "mobile_numbers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."partner_profit_snapshots"
    ADD CONSTRAINT "partner_profit_snapshots_partner_id_date_key_key" UNIQUE ("partner_id", "date_key");



ALTER TABLE ONLY "public"."partner_profit_snapshots"
    ADD CONSTRAINT "partner_profit_snapshots_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."partners"
    ADD CONSTRAINT "partners_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."retailers"
    ADD CONSTRAINT "retailers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rollback_points"
    ADD CONSTRAINT "rollback_points_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rollback_snapshots"
    ADD CONSTRAINT "rollback_snapshots_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sync_locks"
    ADD CONSTRAINT "sync_locks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sync_state"
    ADD CONSTRAINT "sync_state_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."system_config"
    ADD CONSTRAINT "system_config_pkey" PRIMARY KEY ("key");



ALTER TABLE ONLY "public"."system_profit_snapshots"
    ADD CONSTRAINT "system_profit_snapshots_pkey" PRIMARY KEY ("date_key");



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transactions_bybit_order_id_key" UNIQUE ("bybit_order_id");



ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."uid_mapping"
    ADD CONSTRAINT "uid_mapping_pkey" PRIMARY KEY ("firebase_uid");



ALTER TABLE ONLY "public"."usd_exchange"
    ADD CONSTRAINT "usd_exchange_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_firebase_uid_key" UNIQUE ("firebase_uid");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "idx_daily_stats_unique_collector_day" ON "public"."daily_stats" USING "btree" ("year", "month", "day", "collector_id");



CREATE INDEX "idx_financial_ledger_bybit_order_id" ON "public"."financial_ledger" USING "btree" ("bybit_order_id");



CREATE INDEX "idx_financial_ledger_created_by_uid" ON "public"."financial_ledger" USING "btree" ("created_by_uid");



CREATE INDEX "idx_financial_ledger_related_ledger_id" ON "public"."financial_ledger" USING "btree" ("related_ledger_id");



CREATE INDEX "idx_financial_ledger_timestamp" ON "public"."financial_ledger" USING "btree" ("timestamp");



CREATE INDEX "idx_financial_ledger_type" ON "public"."financial_ledger" USING "btree" ("type");



CREATE INDEX "idx_investors_status" ON "public"."investors" USING "btree" ("status");



CREATE INDEX "idx_loans_status" ON "public"."loans" USING "btree" ("status");



CREATE INDEX "idx_retailers_assigned_collector_id" ON "public"."retailers" USING "btree" ("assigned_collector_id");



CREATE INDEX "idx_transactions_bybit_order_id" ON "public"."transactions" USING "btree" ("bybit_order_id");



CREATE INDEX "idx_transactions_phone_number" ON "public"."transactions" USING "btree" ("phone_number");



CREATE OR REPLACE TRIGGER "trg_sync_retailer_pending_debt" BEFORE INSERT OR UPDATE OF "total_assigned", "total_collected", "insta_pay_total_assigned", "insta_pay_total_collected" ON "public"."retailers" FOR EACH ROW EXECUTE FUNCTION "public"."sync_retailer_pending_debt"();



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "fk_users_retailer" FOREIGN KEY ("retailer_id") REFERENCES "public"."retailers"("id");



ALTER TABLE ONLY "public"."investor_profit_snapshots"
    ADD CONSTRAINT "investor_profit_snapshots_investor_id_fkey" FOREIGN KEY ("investor_id") REFERENCES "public"."investors"("id");



ALTER TABLE ONLY "public"."partner_profit_snapshots"
    ADD CONSTRAINT "partner_profit_snapshots_partner_id_fkey" FOREIGN KEY ("partner_id") REFERENCES "public"."partners"("id");



ALTER TABLE ONLY "public"."rollback_snapshots"
    ADD CONSTRAINT "rollback_snapshots_point_id_fkey" FOREIGN KEY ("point_id") REFERENCES "public"."rollback_points"("id") ON DELETE CASCADE;



CREATE POLICY "Authenticated access bank_accounts" ON "public"."bank_accounts" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated access collectors" ON "public"."collectors" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated access financial_ledger" ON "public"."financial_ledger" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated access investor_profit_snapshots" ON "public"."investor_profit_snapshots" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated access investors" ON "public"."investors" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated access loans" ON "public"."loans" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated access mobile_numbers" ON "public"."mobile_numbers" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated access partner_profit_snapshots" ON "public"."partner_profit_snapshots" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated access partners" ON "public"."partners" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated access retailers" ON "public"."retailers" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated access sync_state" ON "public"."sync_state" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated access transactions" ON "public"."transactions" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated access usd_exchange" ON "public"."usd_exchange" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated read daily_flow_summary" ON "public"."daily_flow_summary" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read system_config" ON "public"."system_config" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read system_profit_snapshots" ON "public"."system_profit_snapshots" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read users" ON "public"."users" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated write daily_flow_summary" ON "public"."daily_flow_summary" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated write system_config" ON "public"."system_config" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated write system_profit_snapshots" ON "public"."system_profit_snapshots" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Users can update own profile" ON "public"."users" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id"));



ALTER TABLE "public"."bank_accounts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bank_accounts_read" ON "public"."bank_accounts" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."collectors" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "collectors_read" ON "public"."collectors" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."daily_flow_summary" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "daily_flow_summary_read" ON "public"."daily_flow_summary" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."daily_stats" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "daily_stats_read" ON "public"."daily_stats" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."financial_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."investor_profit_snapshots" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "investor_profit_snapshots_read" ON "public"."investor_profit_snapshots" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."investors" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "investors_read" ON "public"."investors" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "ledger_admin_finance_read" ON "public"."financial_ledger" FOR SELECT TO "authenticated" USING ("public"."has_role"(ARRAY['ADMIN'::"text", 'FINANCE'::"text"]));



CREATE POLICY "ledger_collector_read" ON "public"."financial_ledger" FOR SELECT TO "authenticated" USING (((("created_by_uid" = ("auth"."uid"())::"text") OR ("created_by_uid" = "public"."get_my_firebase_uid"())) AND "public"."has_role"(ARRAY['COLLECTOR'::"text"])));



ALTER TABLE "public"."loans" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "loans_read" ON "public"."loans" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."mobile_numbers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "mobile_numbers_read" ON "public"."mobile_numbers" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."partner_profit_snapshots" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "partner_profit_snapshots_read" ON "public"."partner_profit_snapshots" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."partners" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "partners_read" ON "public"."partners" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."retailers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "retailers_read" ON "public"."retailers" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."rollback_points" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rollback_points_read" ON "public"."rollback_points" FOR SELECT TO "authenticated" USING ("public"."has_role"(ARRAY['ADMIN'::"text", 'FINANCE'::"text"]));



ALTER TABLE "public"."rollback_snapshots" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rollback_snapshots_read" ON "public"."rollback_snapshots" FOR SELECT TO "authenticated" USING ("public"."has_role"(ARRAY['ADMIN'::"text", 'FINANCE'::"text"]));



ALTER TABLE "public"."sync_locks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sync_locks_read" ON "public"."sync_locks" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."sync_state" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sync_state_read" ON "public"."sync_state" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."system_config" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "system_config_read" ON "public"."system_config" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."system_profit_snapshots" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "system_profit_snapshots_read" ON "public"."system_profit_snapshots" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."transactions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "transactions_authenticated_read" ON "public"."transactions" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."uid_mapping" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "uid_mapping_read" ON "public"."uid_mapping" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."usd_exchange" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "usd_exchange_read" ON "public"."usd_exchange" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users_admin_read" ON "public"."users" FOR SELECT TO "authenticated" USING ("public"."is_admin"());



CREATE POLICY "users_self_read" ON "public"."users" FOR SELECT TO "authenticated" USING ((("firebase_uid" = ("auth"."uid"())::"text") OR ("id" = "auth"."uid"())));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";









GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";














































































































































































GRANT ALL ON FUNCTION "public"."acquire_sync_lock"("p_owner_id" "text", "p_ttl_ms" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."acquire_sync_lock"("p_owner_id" "text", "p_ttl_ms" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."acquire_sync_lock"("p_owner_id" "text", "p_ttl_ms" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."apply_mobile_number_usage_delta"("p_number_id" "uuid", "p_amount_delta" numeric, "p_direction" "text", "p_timestamp_ms" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."apply_mobile_number_usage_delta"("p_number_id" "uuid", "p_amount_delta" numeric, "p_direction" "text", "p_timestamp_ms" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."apply_mobile_number_usage_delta"("p_number_id" "uuid", "p_amount_delta" numeric, "p_direction" "text", "p_timestamp_ms" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."collect_retailer_cash_tx"("p_collector_id" "text", "p_retailer_id" "uuid", "p_amount" numeric, "p_vf_amount" numeric, "p_insta_pay_amount" numeric, "p_notes" "text", "p_added_to_collected" numeric, "p_added_to_credit" numeric, "p_uid" "text", "p_timestamp" bigint, "p_insta_tx_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."collect_retailer_cash_tx"("p_collector_id" "text", "p_retailer_id" "uuid", "p_amount" numeric, "p_vf_amount" numeric, "p_insta_pay_amount" numeric, "p_notes" "text", "p_added_to_collected" numeric, "p_added_to_credit" numeric, "p_uid" "text", "p_timestamp" bigint, "p_insta_tx_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."collect_retailer_cash_tx"("p_collector_id" "text", "p_retailer_id" "uuid", "p_amount" numeric, "p_vf_amount" numeric, "p_insta_pay_amount" numeric, "p_notes" "text", "p_added_to_collected" numeric, "p_added_to_credit" numeric, "p_uid" "text", "p_timestamp" bigint, "p_insta_tx_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."correct_financial_ledger_entry"("p_ledger_id" "uuid", "p_new_amount" numeric, "p_new_notes" "text", "p_created_by_uid" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."correct_financial_ledger_entry"("p_ledger_id" "uuid", "p_new_amount" numeric, "p_new_notes" "text", "p_created_by_uid" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."correct_financial_ledger_entry"("p_ledger_id" "uuid", "p_new_amount" numeric, "p_new_notes" "text", "p_created_by_uid" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."deduct_bank_balance"("p_bank_id" "uuid", "p_amount" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."deduct_bank_balance"("p_bank_id" "uuid", "p_amount" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."deduct_bank_balance"("p_bank_id" "uuid", "p_amount" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."deduct_collector_cash"("p_collector_id" "text", "p_amount" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."deduct_collector_cash"("p_collector_id" "text", "p_amount" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."deduct_collector_cash"("p_collector_id" "text", "p_amount" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."deposit_collector_cash_tx"("p_collector_id" "text", "p_bank_account_id" "uuid", "p_amount" numeric, "p_notes" "text", "p_uid" "text", "p_timestamp" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."deposit_collector_cash_tx"("p_collector_id" "text", "p_bank_account_id" "uuid", "p_amount" numeric, "p_notes" "text", "p_uid" "text", "p_timestamp" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."deposit_collector_cash_tx"("p_collector_id" "text", "p_bank_account_id" "uuid", "p_amount" numeric, "p_notes" "text", "p_uid" "text", "p_timestamp" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_business_health"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_business_health"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_business_health"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_daily_performance"("p_start_date_ts" bigint, "p_end_date_ts" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."get_daily_performance"("p_start_date_ts" bigint, "p_end_date_ts" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_daily_performance"("p_start_date_ts" bigint, "p_end_date_ts" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_firebase_uid"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_firebase_uid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_firebase_uid"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_my_user_info"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_my_user_info"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_user_info"() TO "service_role";



GRANT ALL ON FUNCTION "public"."has_role"("target_roles" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."has_role"("target_roles" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_role"("target_roles" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_mobile_number_usage"("p_number_id" "uuid", "p_amount_delta" numeric, "p_direction" "text", "p_timestamp_ms" bigint, "p_require_sufficient_balance" boolean, "p_clamp_at_zero" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."increment_mobile_number_usage"("p_number_id" "uuid", "p_amount_delta" numeric, "p_direction" "text", "p_timestamp_ms" bigint, "p_require_sufficient_balance" boolean, "p_clamp_at_zero" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_mobile_number_usage"("p_number_id" "uuid", "p_amount_delta" numeric, "p_direction" "text", "p_timestamp_ms" bigint, "p_require_sufficient_balance" boolean, "p_clamp_at_zero" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."issue_loan"("p_source_type" "text", "p_source_id" "text", "p_borrower_name" "text", "p_borrower_phone" "text", "p_amount" numeric, "p_notes" "text", "p_created_by_uid" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."issue_loan"("p_source_type" "text", "p_source_id" "text", "p_borrower_name" "text", "p_borrower_phone" "text", "p_amount" numeric, "p_notes" "text", "p_created_by_uid" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."issue_loan"("p_source_type" "text", "p_source_id" "text", "p_borrower_name" "text", "p_borrower_phone" "text", "p_amount" numeric, "p_notes" "text", "p_created_by_uid" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."process_bybit_order_sync"("p_order_id" "text", "p_side" integer, "p_amount" numeric, "p_price" numeric, "p_quantity" numeric, "p_currency" "text", "p_token" "text", "p_timestamp_ms" bigint, "p_payment_method" "text", "p_chat_history" "text", "p_matched_phone" "text", "p_matched_phone_id" "uuid", "p_from_id" "text", "p_from_label" "text", "p_to_id" "text", "p_to_label" "text", "p_is_vodafone_buy" boolean, "p_bank_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."process_bybit_order_sync"("p_order_id" "text", "p_side" integer, "p_amount" numeric, "p_price" numeric, "p_quantity" numeric, "p_currency" "text", "p_token" "text", "p_timestamp_ms" bigint, "p_payment_method" "text", "p_chat_history" "text", "p_matched_phone" "text", "p_matched_phone_id" "uuid", "p_from_id" "text", "p_from_label" "text", "p_to_id" "text", "p_to_label" "text", "p_is_vodafone_buy" boolean, "p_bank_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."process_bybit_order_sync"("p_order_id" "text", "p_side" integer, "p_amount" numeric, "p_price" numeric, "p_quantity" numeric, "p_currency" "text", "p_token" "text", "p_timestamp_ms" bigint, "p_payment_method" "text", "p_chat_history" "text", "p_matched_phone" "text", "p_matched_phone_id" "uuid", "p_from_id" "text", "p_from_label" "text", "p_to_id" "text", "p_to_label" "text", "p_is_vodafone_buy" boolean, "p_bank_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."record_expense"("p_type" "text", "p_amount" numeric, "p_target_id" "text", "p_category" "text", "p_notes" "text", "p_created_by_uid" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."record_expense"("p_type" "text", "p_amount" numeric, "p_target_id" "text", "p_category" "text", "p_notes" "text", "p_created_by_uid" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_expense"("p_type" "text", "p_amount" numeric, "p_target_id" "text", "p_category" "text", "p_notes" "text", "p_created_by_uid" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."record_investor_capital"("p_name" "text", "p_phone" "text", "p_invested_amount" numeric, "p_initial_business_capital" numeric, "p_profit_share_percent" numeric, "p_investment_date" bigint, "p_period_days" integer, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."record_investor_capital"("p_name" "text", "p_phone" "text", "p_invested_amount" numeric, "p_initial_business_capital" numeric, "p_profit_share_percent" numeric, "p_investment_date" bigint, "p_period_days" integer, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_investor_capital"("p_name" "text", "p_phone" "text", "p_invested_amount" numeric, "p_initial_business_capital" numeric, "p_profit_share_percent" numeric, "p_investment_date" bigint, "p_period_days" integer, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."record_investor_payout"("p_investor_id" "uuid", "p_amount" numeric, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."record_investor_payout"("p_investor_id" "uuid", "p_amount" numeric, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_investor_payout"("p_investor_id" "uuid", "p_amount" numeric, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."record_loan_repayment"("p_loan_id" "uuid", "p_amount" numeric, "p_created_by_uid" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."record_loan_repayment"("p_loan_id" "uuid", "p_amount" numeric, "p_created_by_uid" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_loan_repayment"("p_loan_id" "uuid", "p_amount" numeric, "p_created_by_uid" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."record_partner_payout"("p_partner_id" "uuid", "p_amount" numeric, "p_payment_source_type" "text", "p_payment_source_id" "text", "p_notes" "text", "p_created_by_uid" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."record_partner_payout"("p_partner_id" "uuid", "p_amount" numeric, "p_payment_source_type" "text", "p_payment_source_id" "text", "p_notes" "text", "p_created_by_uid" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_partner_payout"("p_partner_id" "uuid", "p_amount" numeric, "p_payment_source_type" "text", "p_payment_source_id" "text", "p_notes" "text", "p_created_by_uid" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."release_sync_lock"("p_owner_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."release_sync_lock"("p_owner_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."release_sync_lock"("p_owner_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."reset_daily_limits"() TO "anon";
GRANT ALL ON FUNCTION "public"."reset_daily_limits"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."reset_daily_limits"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_retailer_pending_debt"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_retailer_pending_debt"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_retailer_pending_debt"() TO "service_role";



GRANT ALL ON FUNCTION "public"."upsert_daily_flow_summary"("p_date_key" "text", "p_vf_delta" numeric, "p_insta_delta" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."upsert_daily_flow_summary"("p_date_key" "text", "p_vf_delta" numeric, "p_insta_delta" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."upsert_daily_flow_summary"("p_date_key" "text", "p_vf_delta" numeric, "p_insta_delta" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."withdraw_investor_capital"("p_investor_id" "uuid", "p_amount" numeric, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."withdraw_investor_capital"("p_investor_id" "uuid", "p_amount" numeric, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."withdraw_investor_capital"("p_investor_id" "uuid", "p_amount" numeric, "p_bank_account_id" "uuid", "p_notes" "text", "p_created_by_uid" "text") TO "service_role";
























GRANT ALL ON TABLE "public"."bank_accounts" TO "anon";
GRANT ALL ON TABLE "public"."bank_accounts" TO "authenticated";
GRANT ALL ON TABLE "public"."bank_accounts" TO "service_role";



GRANT ALL ON TABLE "public"."collectors" TO "anon";
GRANT ALL ON TABLE "public"."collectors" TO "authenticated";
GRANT ALL ON TABLE "public"."collectors" TO "service_role";



GRANT ALL ON TABLE "public"."daily_flow_summary" TO "anon";
GRANT ALL ON TABLE "public"."daily_flow_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."daily_flow_summary" TO "service_role";



GRANT ALL ON TABLE "public"."daily_stats" TO "anon";
GRANT ALL ON TABLE "public"."daily_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."daily_stats" TO "service_role";



GRANT ALL ON TABLE "public"."financial_ledger" TO "anon";
GRANT ALL ON TABLE "public"."financial_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."financial_ledger" TO "service_role";



GRANT ALL ON TABLE "public"."investor_profit_snapshots" TO "anon";
GRANT ALL ON TABLE "public"."investor_profit_snapshots" TO "authenticated";
GRANT ALL ON TABLE "public"."investor_profit_snapshots" TO "service_role";



GRANT ALL ON TABLE "public"."investors" TO "anon";
GRANT ALL ON TABLE "public"."investors" TO "authenticated";
GRANT ALL ON TABLE "public"."investors" TO "service_role";



GRANT ALL ON TABLE "public"."loans" TO "anon";
GRANT ALL ON TABLE "public"."loans" TO "authenticated";
GRANT ALL ON TABLE "public"."loans" TO "service_role";



GRANT ALL ON TABLE "public"."mobile_numbers" TO "anon";
GRANT ALL ON TABLE "public"."mobile_numbers" TO "authenticated";
GRANT ALL ON TABLE "public"."mobile_numbers" TO "service_role";



GRANT ALL ON TABLE "public"."partner_profit_snapshots" TO "anon";
GRANT ALL ON TABLE "public"."partner_profit_snapshots" TO "authenticated";
GRANT ALL ON TABLE "public"."partner_profit_snapshots" TO "service_role";



GRANT ALL ON TABLE "public"."partners" TO "anon";
GRANT ALL ON TABLE "public"."partners" TO "authenticated";
GRANT ALL ON TABLE "public"."partners" TO "service_role";



GRANT ALL ON TABLE "public"."retailers" TO "anon";
GRANT ALL ON TABLE "public"."retailers" TO "authenticated";
GRANT ALL ON TABLE "public"."retailers" TO "service_role";



GRANT ALL ON TABLE "public"."rollback_points" TO "anon";
GRANT ALL ON TABLE "public"."rollback_points" TO "authenticated";
GRANT ALL ON TABLE "public"."rollback_points" TO "service_role";



GRANT ALL ON TABLE "public"."rollback_snapshots" TO "anon";
GRANT ALL ON TABLE "public"."rollback_snapshots" TO "authenticated";
GRANT ALL ON TABLE "public"."rollback_snapshots" TO "service_role";



GRANT ALL ON TABLE "public"."sync_locks" TO "anon";
GRANT ALL ON TABLE "public"."sync_locks" TO "authenticated";
GRANT ALL ON TABLE "public"."sync_locks" TO "service_role";



GRANT ALL ON TABLE "public"."sync_state" TO "anon";
GRANT ALL ON TABLE "public"."sync_state" TO "authenticated";
GRANT ALL ON TABLE "public"."sync_state" TO "service_role";



GRANT ALL ON TABLE "public"."system_config" TO "anon";
GRANT ALL ON TABLE "public"."system_config" TO "authenticated";
GRANT ALL ON TABLE "public"."system_config" TO "service_role";



GRANT ALL ON TABLE "public"."system_profit_snapshots" TO "anon";
GRANT ALL ON TABLE "public"."system_profit_snapshots" TO "authenticated";
GRANT ALL ON TABLE "public"."system_profit_snapshots" TO "service_role";



GRANT ALL ON TABLE "public"."transactions" TO "anon";
GRANT ALL ON TABLE "public"."transactions" TO "authenticated";
GRANT ALL ON TABLE "public"."transactions" TO "service_role";



GRANT ALL ON TABLE "public"."uid_mapping" TO "anon";
GRANT ALL ON TABLE "public"."uid_mapping" TO "authenticated";
GRANT ALL ON TABLE "public"."uid_mapping" TO "service_role";



GRANT ALL ON TABLE "public"."usd_exchange" TO "anon";
GRANT ALL ON TABLE "public"."usd_exchange" TO "authenticated";
GRANT ALL ON TABLE "public"."usd_exchange" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































