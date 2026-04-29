-- Missing RPCs for Vodafone Distribution System

-- 1. distribute_vf_cash
CREATE OR REPLACE FUNCTION public.distribute_vf_cash(
  p_retailer_id UUID,
  p_from_vf_number_id UUID,
  p_amount NUMERIC,
  p_fees NUMERIC,
  p_charge_fees_to_retailer BOOLEAN,
  p_apply_credit BOOLEAN,
  p_created_by_uid TEXT,
  p_notes TEXT
) RETURNS VOID AS $$
DECLARE
  v_retailer RECORD;
  v_discount_per_1000 NUMERIC;
  v_discount_amount NUMERIC;
  v_fee_to_charge NUMERIC;
  v_actual_debt_increase NUMERIC;
  v_credit_used NUMERIC := 0.0;
  v_total_deduction NUMERIC;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  v_tx_id UUID := gen_random_uuid();
  v_cash_tx_id UUID := gen_random_uuid();
  v_vf_phone TEXT;
BEGIN
  -- 1. Fetch retailer and VF phone
  SELECT * INTO v_retailer FROM retailers WHERE id = p_retailer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Retailer not found.'; END IF;

  SELECT phone_number INTO v_vf_phone FROM mobile_numbers WHERE id = p_from_vf_number_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'VF Number not found.'; END IF;

  -- 2. Compute amounts
  v_discount_per_1000 := COALESCE(v_retailer.discount_per_1000, 0);
  v_discount_amount := (p_amount / 1000.0) * v_discount_per_1000;
  v_fee_to_charge := CASE WHEN p_charge_fees_to_retailer THEN p_fees ELSE 0.0 END;
  v_actual_debt_increase := CEIL(p_amount + v_discount_amount + v_fee_to_charge);
  
  IF p_apply_credit AND v_retailer.credit > 0 THEN
    v_credit_used := LEAST(v_retailer.credit, v_actual_debt_increase);
    v_actual_debt_increase := v_actual_debt_increase - v_credit_used;
  END IF;

  v_total_deduction := p_amount + p_fees;

  -- 3. Atomic deduction from mobile number
  PERFORM public.increment_mobile_number_usage(
    p_from_vf_number_id,
    v_total_deduction,
    'outgoing',
    v_now_ts,
    true
  );

  -- 4. Insert DISTRIBUTE_VFCASH ledger entry
  INSERT INTO financial_ledger (
    id, type, amount, from_id, from_label, to_id, to_label,
    created_by_uid, notes, timestamp, generated_transaction_id
  ) VALUES (
    v_tx_id, 'DISTRIBUTE_VFCASH', p_amount, 
    p_from_vf_number_id::TEXT, v_vf_phone, 
    p_retailer_id::TEXT, v_retailer.name,
    p_created_by_uid, 
    TRIM(COALESCE(p_notes, '') || ' (Debt +' || v_actual_debt_increase || ' EGP' || CASE WHEN v_credit_used > 0 THEN ', -' || v_credit_used || ' Credit Used' ELSE '' END || ')'),
    v_now_ts, v_cash_tx_id
  );

  -- 5. Insert transaction row
  INSERT INTO transactions (
    id, phone_number, amount, bybit_order_id, side, status, timestamp, related_ledger_id, payment_method
  ) VALUES (
    v_cash_tx_id, v_vf_phone, v_total_deduction, 
    'DIST-' || LEFT(v_tx_id::TEXT, 8), 0, 'COMPLETED', now(), v_tx_id, 'Vodafone Distribution'
  );

  -- 6. Update retailer
  UPDATE retailers SET
    total_assigned = total_assigned + v_actual_debt_increase,
    credit = credit - v_credit_used,
    last_updated_at = now()
  WHERE id = p_retailer_id;

  -- 7. Handle fees
  IF p_fees > 0 THEN
    INSERT INTO financial_ledger (
      type, amount, from_id, from_label, created_by_uid, 
      related_ledger_id, timestamp, notes
    ) VALUES (
      'EXPENSE_VFCASH_FEE', p_fees, 
      p_from_vf_number_id::TEXT, v_vf_phone, 
      p_created_by_uid, v_tx_id, v_now_ts,
      'Distribution fee for ' || v_retailer.name
    );
  END IF;

  -- 8. Upsert daily flow summary
  PERFORM public.upsert_daily_flow_summary(
    TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD'),
    p_amount,
    0
  );

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. distribute_insta_pay
CREATE OR REPLACE FUNCTION public.distribute_insta_pay(
  p_retailer_id UUID,
  p_bank_account_id UUID,
  p_amount NUMERIC,
  p_fees NUMERIC,
  p_apply_credit BOOLEAN,
  p_created_by_uid TEXT,
  p_notes TEXT
) RETURNS VOID AS $$
DECLARE
  v_retailer RECORD;
  v_bank RECORD;
  v_profit_per_1000 NUMERIC;
  v_profit_amount NUMERIC;
  v_actual_debt_increase NUMERIC;
  v_credit_used NUMERIC := 0.0;
  v_total_deduction NUMERIC;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  v_tx_id UUID := gen_random_uuid();
BEGIN
  -- 1. Fetch data
  SELECT * INTO v_retailer FROM retailers WHERE id = p_retailer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Retailer not found.'; END IF;

  SELECT * INTO v_bank FROM bank_accounts WHERE id = p_bank_account_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Bank account not found.'; END IF;

  -- 2. Compute amounts
  v_profit_per_1000 := COALESCE(v_retailer.insta_pay_profit_per_1000, 0);
  v_profit_amount := (p_amount / 1000.0) * v_profit_per_1000;
  v_actual_debt_increase := CEIL(p_amount + v_profit_amount);
  
  IF p_apply_credit AND v_retailer.credit > 0 THEN
    v_credit_used := LEAST(v_retailer.credit, v_actual_debt_increase);
    v_actual_debt_increase := v_actual_debt_increase - v_credit_used;
  END IF;

  v_total_deduction := p_amount + p_fees;

  -- 3. Atomic deduction from bank
  UPDATE bank_accounts SET
    balance = balance - v_total_deduction,
    last_updated_at = now()
  WHERE id = p_bank_account_id AND balance >= v_total_deduction;
  
  IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient bank balance.'; END IF;

  -- 4. Insert DISTRIBUTE_INSTAPAY ledger entry
  INSERT INTO financial_ledger (
    id, type, amount, from_id, from_label, to_id, to_label,
    created_by_uid, notes, timestamp
  ) VALUES (
    v_tx_id, 'DISTRIBUTE_INSTAPAY', p_amount, 
    p_bank_account_id::TEXT, v_bank.bank_name, 
    p_retailer_id::TEXT, v_retailer.name,
    p_created_by_uid, 
    TRIM(COALESCE(p_notes, '') || ' (Debt +' || v_actual_debt_increase || ' EGP' || CASE WHEN v_credit_used > 0 THEN ', -' || v_credit_used || ' Credit Used' ELSE '' END || ')'),
    v_now_ts
  );

  -- 5. Handle profit
  IF v_profit_amount > 0 THEN
    INSERT INTO financial_ledger (
      type, amount, created_by_uid, related_ledger_id, timestamp, notes
    ) VALUES (
      'INSTAPAY_DIST_PROFIT', v_profit_amount, 
      p_created_by_uid, v_tx_id, v_now_ts,
      'Profit from InstaPay distribution to ' || v_retailer.name
    );
  END IF;

  -- 6. Handle fees
  IF p_fees > 0 THEN
    INSERT INTO financial_ledger (
      type, amount, from_id, from_label, created_by_uid, 
      related_ledger_id, timestamp, notes
    ) VALUES (
      'EXPENSE_INSTAPAY_FEE', p_fees, 
      p_bank_account_id::TEXT, v_bank.bank_name, 
      p_created_by_uid, v_tx_id, v_now_ts,
      'InstaPay distribution fee for ' || v_retailer.name
    );
  END IF;

  -- 7. Update retailer
  UPDATE retailers SET
    insta_pay_total_assigned = insta_pay_total_assigned + v_actual_debt_increase,
    credit = credit - v_credit_used,
    last_updated_at = now()
  WHERE id = p_retailer_id;

  -- 8. Upsert daily flow summary
  PERFORM public.upsert_daily_flow_summary(
    TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD'),
    0,
    p_amount
  );

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. collect_retailer_cash
CREATE OR REPLACE FUNCTION public.collect_retailer_cash(
  p_collector_id TEXT,
  p_retailer_id UUID,
  p_amount NUMERIC,
  p_vf_amount NUMERIC,
  p_insta_pay_amount NUMERIC,
  p_created_by_uid TEXT,
  p_notes TEXT
) RETURNS VOID AS $$
DECLARE
  v_retailer RECORD;
  v_pending_debt NUMERIC;
  v_insta_pending_debt NUMERIC;
  v_added_to_collected NUMERIC;
  v_added_to_credit NUMERIC;
  v_final_notes TEXT;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
BEGIN
  -- 1. Fetch retailer
  SELECT * INTO v_retailer FROM retailers WHERE id = p_retailer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Retailer not found.'; END IF;

  -- 2. Compute VF split
  v_pending_debt := GREATEST(0, v_retailer.total_assigned - v_retailer.total_collected);
  v_added_to_collected := LEAST(p_vf_amount, v_pending_debt);
  v_added_to_credit := p_vf_amount - v_added_to_collected;

  -- 3. Prepare notes
  v_final_notes := COALESCE(p_notes, '');
  IF v_added_to_credit > 0 THEN
    v_final_notes := TRIM('(+' || v_added_to_credit || ' EGP added to Credit) ' || v_final_notes);
  END IF;

  -- 4. Call existing _tx function
  PERFORM public.collect_retailer_cash_tx(
    p_collector_id,
    p_retailer_id,
    p_amount,
    p_vf_amount,
    p_insta_pay_amount,
    v_final_notes,
    v_added_to_collected,
    v_added_to_credit,
    p_created_by_uid,
    v_now_ts
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3.1 Internal Transaction for Collection
DROP FUNCTION IF EXISTS public.collect_retailer_cash_tx(TEXT, UUID, NUMERIC, NUMERIC, NUMERIC, TEXT, NUMERIC, NUMERIC, TEXT, BIGINT, UUID);

CREATE OR REPLACE FUNCTION public.collect_retailer_cash_tx(
  p_collector_id TEXT,
  p_retailer_id UUID,
  p_amount NUMERIC,
  p_vf_amount NUMERIC,
  p_insta_pay_amount NUMERIC,
  p_notes TEXT,
  p_vf_collected NUMERIC,
  p_ip_collected NUMERIC,
  p_added_to_credit NUMERIC,
  p_uid TEXT,
  p_timestamp BIGINT,
  p_insta_tx_id UUID DEFAULT gen_random_uuid()
) RETURNS JSONB AS $$
DECLARE
  v_main_tx_id UUID := gen_random_uuid();
  v_vf_tx_id UUID := gen_random_uuid();
  v_ip_tx_id UUID := gen_random_uuid();
  v_collector_name TEXT;
  v_retailer_name TEXT;
BEGIN
  -- 1. Update Collector
  UPDATE collectors SET
    cash_on_hand = cash_on_hand + p_amount,
    total_collected = total_collected + p_amount,
    last_updated_at = now()
  WHERE id = p_collector_id
  RETURNING name INTO v_collector_name;

  IF NOT FOUND THEN RAISE EXCEPTION 'Collector not found.'; END IF;

  -- 2. Update Retailer
  UPDATE retailers SET
    total_collected = total_collected + p_vf_collected,
    insta_pay_total_collected = insta_pay_total_collected + p_ip_collected,
    credit = credit + p_added_to_credit,
    last_updated_at = now()
  WHERE id = p_retailer_id
  RETURNING name INTO v_retailer_name;

  IF NOT FOUND THEN RAISE EXCEPTION 'Retailer not found.'; END IF;

  -- 3. Insert Ledger Entries
  -- Record VF Collection
  IF p_vf_collected > 0 OR (p_added_to_credit > 0 AND p_ip_collected = 0) THEN
    INSERT INTO financial_ledger (
      id, type, amount, from_id, from_label, to_id, to_label,
      created_by_uid, notes, timestamp,
      collected_portion, credit_portion
    ) VALUES (
      v_vf_tx_id, 'COLLECT_VFCASH', (p_vf_collected + CASE WHEN p_ip_collected = 0 THEN p_added_to_credit ELSE 0 END),
      p_retailer_id::TEXT, v_retailer_name,
      p_collector_id, v_collector_name,
      p_uid, p_notes, p_timestamp,
      p_vf_collected, CASE WHEN p_ip_collected = 0 THEN p_added_to_credit ELSE 0 END
    );
    v_main_tx_id := v_vf_tx_id;
  END IF;

  -- Record InstaPay Collection
  IF p_ip_collected > 0 THEN
    INSERT INTO financial_ledger (
      id, type, amount, from_id, from_label, to_id, to_label,
      created_by_uid, notes, timestamp,
      collected_portion, credit_portion, related_ledger_id
    ) VALUES (
      v_ip_tx_id, 'COLLECT_INSTAPAY', (p_ip_collected + CASE WHEN p_vf_collected = 0 THEN p_added_to_credit ELSE 0 END),
      p_retailer_id::TEXT, v_retailer_name,
      p_collector_id, v_collector_name,
      p_uid, p_notes, p_timestamp + 1,
      p_ip_collected, CASE WHEN p_vf_collected = 0 THEN p_added_to_credit ELSE 0 END,
      CASE WHEN p_vf_collected > 0 THEN v_vf_tx_id ELSE NULL END
    );
    IF v_main_tx_id = v_vf_tx_id THEN 
       -- keep v_vf_tx_id as main
    ELSE
       v_main_tx_id := v_ip_tx_id;
    END IF;
  END IF;

  -- Fallback if nothing was collected but amount > 0 (pure credit)
  IF p_amount > 0 AND p_vf_collected = 0 AND p_ip_collected = 0 THEN
      INSERT INTO financial_ledger (
        id, type, amount, from_id, from_label, to_id, to_label,
        created_by_uid, notes, timestamp,
        collected_portion, credit_portion
      ) VALUES (
        v_main_tx_id, 'COLLECT_CASH', p_amount,
        p_retailer_id::TEXT, v_retailer_name,
        p_collector_id, v_collector_name,
        p_uid, p_notes, p_timestamp,
        0, p_amount
      );
  END IF;

  RETURN jsonb_build_object('tx_id', v_main_tx_id, 'insta_tx_id', p_insta_tx_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. deposit_collector_cash
CREATE OR REPLACE FUNCTION public.deposit_collector_cash(
  p_collector_id TEXT,
  p_bank_account_id UUID,
  p_amount NUMERIC,
  p_created_by_uid TEXT,
  p_notes TEXT
) RETURNS VOID AS $$
BEGIN
  PERFORM public.deposit_collector_cash_tx(
    p_collector_id,
    p_bank_account_id,
    p_amount,
    p_notes,
    p_created_by_uid,
    (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. deposit_collector_cash_to_vf
CREATE OR REPLACE FUNCTION public.deposit_collector_cash_to_vf(
  p_collector_id TEXT,
  p_vf_number_id UUID,
  p_amount NUMERIC,
  p_created_by_uid TEXT,
  p_notes TEXT
) RETURNS VOID AS $$
DECLARE
  v_collector_name TEXT;
  v_vf_phone TEXT;
  v_fee_rate NUMERIC;
  v_fee_amount NUMERIC;
  v_transferred_amount NUMERIC;
  v_tx_id UUID := gen_random_uuid();
  v_profit_tx_id UUID := gen_random_uuid();
  v_cash_tx_id UUID := gen_random_uuid();
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  v_detail_note TEXT;
BEGIN
  -- 1. Get collector info and deduct cash
  UPDATE collectors SET
    cash_on_hand = cash_on_hand - p_amount,
    total_deposited = total_deposited + p_amount,
    last_updated_at = now()
  WHERE id = p_collector_id AND cash_on_hand >= p_amount
  RETURNING name INTO v_collector_name;
  
  IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient collector cash.'; END IF;

  -- 2. Get VF info and fee rate
  SELECT phone_number INTO v_vf_phone FROM mobile_numbers WHERE id = p_vf_number_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'VF number not found.'; END IF;

  SELECT COALESCE((value->'operation_settings'->>'collectorVfDepositFeePer1000')::NUMERIC, 7) INTO v_fee_rate 
  FROM system_config WHERE key = 'operation_settings';

  -- 3. Calculate amounts
  v_fee_amount := ROUND((p_amount / 1000.0) * v_fee_rate, 2);
  v_transferred_amount := p_amount + v_fee_amount;

  -- 4. Credit VF number (Full transferred amount)
  PERFORM public.increment_mobile_number_usage(
    p_vf_number_id,
    v_transferred_amount,
    'in',
    v_now_ts
  );

  -- 5. Prepare notes
  v_detail_note := 'Transferred ' || v_transferred_amount || ' EGP to ' || v_vf_phone || 
                   ' (Cash ' || p_amount || ' + Profit ' || v_fee_amount || ' @ ' || v_fee_rate || '/1000)';
  
  -- 6. Insert Main Ledger Entry
  INSERT INTO financial_ledger (
    id, type, amount, transferred_amount, fee_amount, fee_rate_per_1000,
    from_id, from_label, to_id, to_label,
    created_by_uid, notes, timestamp, generated_transaction_id
  ) VALUES (
    v_tx_id, 'DEPOSIT_TO_VFCASH', p_amount, v_transferred_amount, v_fee_amount, v_fee_rate,
    p_collector_id, v_collector_name,
    p_vf_number_id::TEXT, v_vf_phone,
    p_created_by_uid, 
    TRIM(COALESCE(p_notes, '') || ' (' || v_detail_note || ')'),
    v_now_ts, v_cash_tx_id
  );

  -- 7. Insert Transaction Entry
  INSERT INTO transactions (
    id, phone_number, amount, bybit_order_id, status, payment_method, side, timestamp, related_ledger_id
  ) VALUES (
    v_cash_tx_id, v_vf_phone, v_transferred_amount,
    'CLDV-' || LEFT(v_tx_id::TEXT, 8), 'COMPLETED', 'Vodafone Collector Deposit', 1, now(), v_tx_id
  );

  -- 8. Record Profit if any
  IF v_fee_amount > 0 THEN
    INSERT INTO financial_ledger (
      id, type, amount, from_id, from_label, to_id, to_label,
      created_by_uid, related_ledger_id, timestamp, notes
    ) VALUES (
      v_profit_tx_id, 'VFCASH_RETAIL_PROFIT', v_fee_amount,
      p_collector_id, v_collector_name,
      p_vf_number_id::TEXT, v_vf_phone,
      p_created_by_uid, v_tx_id, v_now_ts,
      'Collector Vodafone deposit profit'
    );
  END IF;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. transfer_internal_vf_cash
CREATE OR REPLACE FUNCTION public.transfer_internal_vf_cash(
  p_from_vf_id UUID,
  p_to_vf_id UUID,
  p_amount NUMERIC,
  p_fees NUMERIC,
  p_created_by_uid TEXT,
  p_notes TEXT
) RETURNS VOID AS $$
DECLARE
  v_from_phone TEXT;
  v_to_phone TEXT;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
  v_tx_id UUID := gen_random_uuid();
  v_cash_tx_id_src UUID := gen_random_uuid();
  v_cash_tx_id_dst UUID := gen_random_uuid();
BEGIN
  SELECT phone_number INTO v_from_phone FROM mobile_numbers WHERE id = p_from_vf_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Source VF number not found.'; END IF;

  SELECT phone_number INTO v_to_phone FROM mobile_numbers WHERE id = p_to_vf_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Destination VF number not found.'; END IF;

  -- 1. Deduct from source (including fees)
  PERFORM public.increment_mobile_number_usage(
    p_from_vf_id,
    p_amount + p_fees,
    'out',
    v_now_ts,
    true
  );

  -- 2. Credit target
  PERFORM public.increment_mobile_number_usage(
    p_to_vf_id,
    p_amount,
    'in',
    v_now_ts
  );

  -- 3. Record Ledger
  INSERT INTO financial_ledger (
    id, type, amount, from_id, from_label, to_id, to_label,
    created_by_uid, notes, timestamp
  ) VALUES (
    v_tx_id, 'INTERNAL_VF_TRANSFER', p_amount,
    p_from_vf_id::TEXT, v_from_phone,
    p_to_vf_id::TEXT, v_to_phone,
    p_created_by_uid, p_notes, v_now_ts
  );

  -- 4. Record Source Transaction
  INSERT INTO transactions (
    id, phone_number, amount, bybit_order_id, status, side, timestamp, related_ledger_id, payment_method
  ) VALUES (
    v_cash_tx_id_src, v_from_phone, p_amount + p_fees,
    'INT-S-' || LEFT(v_tx_id::TEXT, 8), 'COMPLETED', 0, now(), v_tx_id, 'Internal VF Transfer (Out)'
  );

  -- 5. Record Destination Transaction
  INSERT INTO transactions (
    id, phone_number, amount, bybit_order_id, status, side, timestamp, related_ledger_id, payment_method
  ) VALUES (
    v_cash_tx_id_dst, v_to_phone, p_amount,
    'INT-D-' || LEFT(v_tx_id::TEXT, 8), 'COMPLETED', 1, now(), v_tx_id, 'Internal VF Transfer (In)'
  );

  -- 6. Record Fees
  IF p_fees > 0 THEN
    INSERT INTO financial_ledger (
      type, amount, from_id, from_label, 
      created_by_uid, related_ledger_id, timestamp, notes
    ) VALUES (
      'INTERNAL_VF_TRANSFER_FEE', p_fees,
      p_from_vf_id::TEXT, v_from_phone,
      p_created_by_uid, v_tx_id, v_now_ts,
      'Transfer fee from ' || v_from_phone || ' to ' || v_to_phone
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. delete_financial_transaction
CREATE OR REPLACE FUNCTION public.delete_financial_transaction(
  p_transaction_id UUID
) RETURNS VOID AS $$
DECLARE
  v_ledger RECORD;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
BEGIN
  SELECT * INTO v_ledger FROM financial_ledger WHERE id = p_transaction_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  -- Reverse impact
  IF v_ledger.type = 'DISTRIBUTE_VFCASH' THEN
    PERFORM public.increment_mobile_number_usage(v_ledger.from_id::UUID, -(v_ledger.amount + COALESCE(v_ledger.fee_amount, 0)), 'out', v_now_ts, false, true);
    UPDATE retailers SET 
      total_assigned = total_assigned - public.parse_distribution_debt_increase(v_ledger.notes, v_ledger.amount),
      credit = credit + public.parse_distribution_credit_used(v_ledger.notes)
    WHERE id = v_ledger.to_id::UUID;
  ELSIF v_ledger.type = 'COLLECT_CASH' THEN
    UPDATE collectors SET cash_on_hand = cash_on_hand - v_ledger.amount, total_collected = total_collected - v_ledger.amount WHERE id = v_ledger.to_id;
    UPDATE retailers SET 
      total_collected = total_collected - COALESCE(v_ledger.collected_portion, v_ledger.amount),
      credit = credit - COALESCE(v_ledger.credit_portion, 0)
    WHERE id = v_ledger.from_id::UUID;
  END IF;

  DELETE FROM financial_ledger WHERE id = p_transaction_id OR related_ledger_id = p_transaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. credit_return
CREATE OR REPLACE FUNCTION public.credit_return(
  p_retailer_id UUID,
  p_amount NUMERIC,
  p_fees NUMERIC,
  p_target_vf_id UUID,
  p_created_by_uid TEXT,
  p_notes TEXT
) RETURNS VOID AS $$
DECLARE
  v_retailer_name TEXT;
  v_vf_phone TEXT;
  v_tx_id UUID := gen_random_uuid();
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
BEGIN
  -- 1. Deduct from retailer credit
  UPDATE retailers SET
    credit = credit - p_amount,
    last_updated_at = now()
  WHERE id = p_retailer_id AND credit >= p_amount
  RETURNING name INTO v_retailer_name;
  
  IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient retailer credit.'; END IF;

  -- 2. Credit VF number
  SELECT phone_number INTO v_vf_phone FROM mobile_numbers WHERE id = p_target_vf_id;
  PERFORM public.increment_mobile_number_usage(
    p_target_vf_id,
    p_amount - p_fees,
    'in',
    v_now_ts
  );

  -- 3. Record ledger entry (Credit Return)
  INSERT INTO financial_ledger (
    id, type, amount, from_id, from_label, to_id, to_label,
    created_by_uid, notes, timestamp
  ) VALUES (
    v_tx_id, 'CREDIT_RETURN', p_amount,
    p_retailer_id::TEXT, v_retailer_name,
    p_target_vf_id::TEXT, v_vf_phone,
    p_created_by_uid, p_notes, v_now_ts
  );

  -- 4. Record fees if any
  IF p_fees > 0 THEN
    INSERT INTO financial_ledger (
      type, amount, from_id, from_label,
      related_ledger_id, timestamp, notes
    ) VALUES (
      'CREDIT_RETURN_FEE', p_fees,
      p_target_vf_id::TEXT, v_vf_phone,
      v_tx_id, v_now_ts,
      'Credit return fee for ' || v_retailer_name
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. round_all_retailer_assignments
CREATE OR REPLACE FUNCTION public.round_all_retailer_assignments()
RETURNS VOID AS $$
BEGIN
  UPDATE retailers SET
    total_assigned = ROUND(total_assigned, 2),
    total_collected = ROUND(total_collected, 2),
    credit = ROUND(credit, 2),
    insta_pay_total_assigned = ROUND(insta_pay_total_assigned, 2),
    insta_pay_total_collected = ROUND(insta_pay_total_collected, 2);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. correct_financial_transaction (wrapper)
CREATE OR REPLACE FUNCTION public.correct_financial_transaction(
  p_ledger_id UUID,
  p_new_amount NUMERIC,
  p_new_notes TEXT,
  p_created_by_uid TEXT
) RETURNS VOID AS $$
BEGIN
  PERFORM public.correct_financial_ledger_entry(
    p_ledger_id,
    p_new_amount,
    p_new_notes,
    p_created_by_uid
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper to parse debt increase from notes
CREATE OR REPLACE FUNCTION public.parse_distribution_debt_increase(p_notes TEXT, p_fallback NUMERIC)
RETURNS NUMERIC AS $$
DECLARE
  v_match TEXT;
BEGIN
  v_match := substring(p_notes from 'Debt \+([0-9.]+) EGP');
  IF v_match IS NOT NULL THEN
    RETURN v_match::NUMERIC;
  ELSE
    RETURN p_fallback;
  END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- Helper to parse credit used from notes
CREATE OR REPLACE FUNCTION public.parse_distribution_credit_used(p_notes TEXT)
RETURNS NUMERIC AS $$
DECLARE
  v_match TEXT;
BEGIN
  v_match := substring(p_notes from '-([0-9.]+) Credit Used');
  IF v_match IS NOT NULL THEN
    RETURN v_match::NUMERIC;
  ELSE
    RETURN 0;
  END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- 11. repair_system_state
CREATE OR REPLACE FUNCTION public.repair_system_state()
RETURNS JSONB AS $$
DECLARE
  v_result JSONB;
  v_sim_count INT := 0;
  v_retailer_count INT := 0;
  v_collector_count INT := 0;
  r RECORD;
BEGIN
  -- A. Stop Background Jobs (Stop the corruption)
  BEGIN
    PERFORM cron.unschedule('sync-bybit-orders-job');
    PERFORM cron.unschedule('reset-daily-limits-job');
  EXCEPTION WHEN OTHERS THEN
    -- Ignore if jobs don't exist
  END;

  -- B. Recalculate Mobile Numbers Usage
  UPDATE public.mobile_numbers SET in_total_used = 0, out_total_used = 0, in_daily_used = 0, out_daily_used = 0, in_monthly_used = 0, out_monthly_used = 0;
  
  FOR r IN 
    SELECT to_id, SUM(amount) as total 
    FROM public.financial_ledger 
    WHERE to_id IN (SELECT id::TEXT FROM public.mobile_numbers)
    GROUP BY to_id
  LOOP
    UPDATE public.mobile_numbers SET in_total_used = r.total, in_monthly_used = r.total, in_daily_used = 0 WHERE id = r.to_id::UUID;
    v_sim_count := v_sim_count + 1;
  END LOOP;

  FOR r IN 
    SELECT from_id, SUM(amount + COALESCE(fee_amount, 0)) as total 
    FROM public.financial_ledger 
    WHERE from_id IN (SELECT id::TEXT FROM public.mobile_numbers)
      AND type NOT IN ('INTERNAL_VF_TRANSFER_FEE', 'EXPENSE_VFCASH_FEE')
    GROUP BY from_id
  LOOP
    UPDATE public.mobile_numbers SET out_total_used = r.total, out_monthly_used = r.total, out_daily_used = 0 WHERE id = r.from_id::UUID;
  END LOOP;

  -- C. Recalculate Retailer Debt
  UPDATE public.retailers SET total_assigned = 0, total_collected = 0;
  
  FOR r IN 
    SELECT to_id, SUM(
      CASE 
        WHEN notes ~ 'Debt \+([0-9.]+)' THEN (regexp_match(notes, 'Debt \+([0-9.]+)')::TEXT[])[1]::NUMERIC
        ELSE amount 
      END
    ) as total
  FROM public.financial_ledger 
    WHERE type IN ('DISTRIBUTE_VFCASH', 'DISTRIBUTE_INSTAPAY')
      AND to_id IN (SELECT id::TEXT FROM public.retailers)
    GROUP BY to_id
  LOOP
    UPDATE public.retailers SET total_assigned = r.total WHERE id = r.to_id::UUID;
    v_retailer_count := v_retailer_count + 1;
  END LOOP;

  FOR r IN 
    SELECT from_id, SUM(amount) as total
    FROM public.financial_ledger 
    WHERE type IN ('COLLECT_RETAILER_CASH')
      AND from_id IN (SELECT id::TEXT FROM public.retailers)
    GROUP BY from_id
  LOOP
    UPDATE public.retailers SET total_collected = r.total WHERE id = r.from_id::UUID;
  END LOOP;

  -- D. Recalculate Collector Cash
  UPDATE public.collectors SET cash_on_hand = 0;
  
  FOR r IN 
    SELECT to_id, SUM(amount) as total
    FROM public.financial_ledger 
    WHERE type = 'COLLECT_RETAILER_CASH'
      AND to_id IN (SELECT id::TEXT FROM public.collectors)
    GROUP BY to_id
  LOOP
    UPDATE public.collectors SET cash_on_hand = cash_on_hand + r.total WHERE id = r.to_id::UUID;
    v_collector_count := v_collector_count + 1;
  END LOOP;

  FOR r IN 
    SELECT from_id, SUM(amount) as total
    FROM public.financial_ledger 
    WHERE type IN ('DEPOSIT_COLLECTOR_CASH', 'EXPENSE_BANK')
      AND from_id IN (SELECT id::TEXT FROM public.collectors)
    GROUP BY from_id
  LOOP
    UPDATE public.collectors SET cash_on_hand = cash_on_hand - r.total WHERE id = r.from_id::UUID;
  END LOOP;

  v_result := jsonb_build_object(
    'status', 'success',
    'sims_updated', v_sim_count,
    'retailers_updated', v_retailer_count,
    'collectors_updated', v_collector_count,
    'cron_jobs_disabled', true
  );
  
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 20. pay_investor_profit
CREATE OR REPLACE FUNCTION public.pay_investor_profit(
  p_investor_id UUID,
  p_amount NUMERIC,
  p_bank_account_id UUID,
  p_created_by_uid TEXT,
  p_notes TEXT DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
  v_investor_name TEXT;
  v_bank_name TEXT;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
BEGIN
  -- 1. Deduct from bank balance
  UPDATE bank_accounts SET
    balance = balance - p_amount,
    last_updated_at = now()
  WHERE id = p_bank_account_id AND balance >= p_amount
  RETURNING bank_name INTO v_bank_name;

  IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient bank balance.'; END IF;

  -- 2. Update investor
  UPDATE investors SET
    total_profit_paid = total_profit_paid + p_amount,
    last_paid_at = v_now_ts
  WHERE id = p_investor_id
  RETURNING name INTO v_investor_name;

  IF NOT FOUND THEN RAISE EXCEPTION 'Investor not found.'; END IF;

  -- 3. Record in ledger
  INSERT INTO financial_ledger (
    type, amount, from_id, from_label, to_label, created_by_uid, notes, timestamp
  ) VALUES (
    'INVESTOR_PROFIT_PAID', p_amount,
    p_bank_account_id::TEXT, v_bank_name,
    v_investor_name, p_created_by_uid,
    COALESCE(p_notes, 'Investor Profit Payout'), v_now_ts
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 21. pay_partner_profit
CREATE OR REPLACE FUNCTION public.pay_partner_profit(
  p_partner_id UUID,
  p_amount NUMERIC,
  p_method TEXT, -- 'BANK' or 'VF'
  p_source_id UUID,
  p_created_by_uid TEXT,
  p_notes TEXT DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
  v_partner_name TEXT;
  v_source_label TEXT;
  v_now_ts BIGINT := (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT;
BEGIN
  -- 1. Deduct from source
  IF p_method = 'BANK' THEN
    UPDATE bank_accounts SET
      balance = balance - p_amount,
      last_updated_at = now()
    WHERE id = p_source_id AND balance >= p_amount
    RETURNING bank_name INTO v_source_label;
    
    IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient bank balance.'; END IF;
  ELSIF p_method = 'VF' THEN
    SELECT phone_number INTO v_source_label FROM mobile_numbers WHERE id = p_source_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'VF Number not found.'; END IF;
    
    PERFORM public.increment_mobile_number_usage(p_source_id, p_amount, 'out', v_now_ts);
  ELSE
    RAISE EXCEPTION 'Invalid payment method. Use BANK or VF.';
  END IF;

  -- 2. Update partner
  UPDATE partners SET
    total_profit_paid = total_profit_paid + p_amount,
    last_paid_at = v_now_ts,
    updated_at = v_now_ts
  WHERE id = p_partner_id
  RETURNING name INTO v_partner_name;

  IF NOT FOUND THEN RAISE EXCEPTION 'Partner not found.'; END IF;

  -- 3. Record in ledger
  INSERT INTO financial_ledger (
    type, amount, from_id, from_label, to_label, created_by_uid, notes, timestamp
  ) VALUES (
    CASE WHEN p_method = 'BANK' THEN 'PARTNER_PROFIT_PAID_BANK' ELSE 'PARTNER_PROFIT_PAID_VF' END,
    p_amount, p_source_id::TEXT, v_source_label, v_partner_name,
    p_created_by_uid, COALESCE(p_notes, 'Partner Profit Payout'), v_now_ts
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;