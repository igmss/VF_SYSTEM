


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


CREATE SCHEMA IF NOT EXISTS "auth";


ALTER SCHEMA "auth" OWNER TO "supabase_admin";


CREATE SCHEMA IF NOT EXISTS "extensions";


ALTER SCHEMA "extensions" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE SCHEMA IF NOT EXISTS "storage";


ALTER SCHEMA "storage" OWNER TO "supabase_admin";


CREATE TYPE "auth"."aal_level" AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


ALTER TYPE "auth"."aal_level" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."code_challenge_method" AS ENUM (
    's256',
    'plain'
);


ALTER TYPE "auth"."code_challenge_method" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."factor_status" AS ENUM (
    'unverified',
    'verified'
);


ALTER TYPE "auth"."factor_status" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."factor_type" AS ENUM (
    'totp',
    'webauthn',
    'phone'
);


ALTER TYPE "auth"."factor_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_authorization_status" AS ENUM (
    'pending',
    'approved',
    'denied',
    'expired'
);


ALTER TYPE "auth"."oauth_authorization_status" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_client_type" AS ENUM (
    'public',
    'confidential'
);


ALTER TYPE "auth"."oauth_client_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_registration_type" AS ENUM (
    'dynamic',
    'manual'
);


ALTER TYPE "auth"."oauth_registration_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_response_type" AS ENUM (
    'code'
);


ALTER TYPE "auth"."oauth_response_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."one_time_token_type" AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


ALTER TYPE "auth"."one_time_token_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "storage"."buckettype" AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


ALTER TYPE "storage"."buckettype" OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "auth"."email"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


ALTER FUNCTION "auth"."email"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."email"() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';



CREATE OR REPLACE FUNCTION "auth"."jwt"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


ALTER FUNCTION "auth"."jwt"() OWNER TO "supabase_auth_admin";


CREATE OR REPLACE FUNCTION "auth"."role"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


ALTER FUNCTION "auth"."role"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."role"() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';



CREATE OR REPLACE FUNCTION "auth"."uid"() RETURNS "uuid"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


ALTER FUNCTION "auth"."uid"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."uid"() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';



CREATE OR REPLACE FUNCTION "extensions"."grant_pg_cron_access"() RETURNS "event_trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF EXISTS (
    SELECT
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_cron'
  )
  THEN
    grant usage on schema cron to postgres with grant option;

    alter default privileges in schema cron grant all on tables to postgres with grant option;
    alter default privileges in schema cron grant all on functions to postgres with grant option;
    alter default privileges in schema cron grant all on sequences to postgres with grant option;

    alter default privileges for user supabase_admin in schema cron grant all
        on sequences to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on tables to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on functions to postgres with grant option;

    grant all privileges on all tables in schema cron to postgres with grant option;
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
  END IF;
END;
$$;


ALTER FUNCTION "extensions"."grant_pg_cron_access"() OWNER TO "supabase_admin";


COMMENT ON FUNCTION "extensions"."grant_pg_cron_access"() IS 'Grants access to pg_cron';



CREATE OR REPLACE FUNCTION "extensions"."grant_pg_graphql_access"() RETURNS "event_trigger"
    LANGUAGE "plpgsql"
    AS $_$
DECLARE
    func_is_graphql_resolve bool;
BEGIN
    func_is_graphql_resolve = (
        SELECT n.proname = 'resolve'
        FROM pg_event_trigger_ddl_commands() AS ev
        LEFT JOIN pg_catalog.pg_proc AS n
        ON ev.objid = n.oid
    );

    IF func_is_graphql_resolve
    THEN
        -- Update public wrapper to pass all arguments through to the pg_graphql resolve func
        DROP FUNCTION IF EXISTS graphql_public.graphql;
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language sql
        as $$
            select graphql.resolve(
                query := query,
                variables := coalesce(variables, '{}'),
                "operationName" := "operationName",
                extensions := extensions
            );
        $$;

        -- This hook executes when `graphql.resolve` is created. That is not necessarily the last
        -- function in the extension so we need to grant permissions on existing entities AND
        -- update default permissions to any others that are created after `graphql.resolve`
        grant usage on schema graphql to postgres, anon, authenticated, service_role;
        grant select on all tables in schema graphql to postgres, anon, authenticated, service_role;
        grant execute on all functions in schema graphql to postgres, anon, authenticated, service_role;
        grant all on all sequences in schema graphql to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on tables to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on functions to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on sequences to postgres, anon, authenticated, service_role;

        -- Allow postgres role to allow granting usage on graphql and graphql_public schemas to custom roles
        grant usage on schema graphql_public to postgres with grant option;
        grant usage on schema graphql to postgres with grant option;
    END IF;

END;
$_$;


ALTER FUNCTION "extensions"."grant_pg_graphql_access"() OWNER TO "supabase_admin";


COMMENT ON FUNCTION "extensions"."grant_pg_graphql_access"() IS 'Grants access to pg_graphql';



CREATE OR REPLACE FUNCTION "extensions"."grant_pg_net_access"() RETURNS "event_trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_net'
  )
  THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'supabase_functions_admin'
    )
    THEN
      CREATE USER supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
    END IF;

    GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;

    IF EXISTS (
      SELECT FROM pg_extension
      WHERE extname = 'pg_net'
      -- all versions in use on existing projects as of 2025-02-20
      -- version 0.12.0 onwards don't need these applied
      AND extversion IN ('0.2', '0.6', '0.7', '0.7.1', '0.8', '0.10.0', '0.11.0')
    ) THEN
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;

      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;

      REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;

      GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
    END IF;
  END IF;
END;
$$;


ALTER FUNCTION "extensions"."grant_pg_net_access"() OWNER TO "supabase_admin";


COMMENT ON FUNCTION "extensions"."grant_pg_net_access"() IS 'Grants access to pg_net';



CREATE OR REPLACE FUNCTION "extensions"."pgrst_ddl_watch"() RETURNS "event_trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TRIGGER'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    AND cmd.schema_name is distinct from 'pg_temp'
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


ALTER FUNCTION "extensions"."pgrst_ddl_watch"() OWNER TO "supabase_admin";


CREATE OR REPLACE FUNCTION "extensions"."pgrst_drop_watch"() RETURNS "event_trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'trigger'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $$;


ALTER FUNCTION "extensions"."pgrst_drop_watch"() OWNER TO "supabase_admin";


CREATE OR REPLACE FUNCTION "extensions"."set_graphql_placeholder"() RETURNS "event_trigger"
    LANGUAGE "plpgsql"
    AS $_$
    DECLARE
    graphql_is_dropped bool;
    BEGIN
    graphql_is_dropped = (
        SELECT ev.schema_name = 'graphql_public'
        FROM pg_event_trigger_dropped_objects() AS ev
        WHERE ev.schema_name = 'graphql_public'
    );

    IF graphql_is_dropped
    THEN
        create or replace function graphql_public.graphql(
            "operationName" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language plpgsql
        as $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;
    END IF;

    END;
$_$;


ALTER FUNCTION "extensions"."set_graphql_placeholder"() OWNER TO "supabase_admin";


COMMENT ON FUNCTION "extensions"."set_graphql_placeholder"() IS 'Reintroduces placeholder function for graphql_public.graphql';



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


CREATE OR REPLACE FUNCTION "storage"."allow_any_operation"("expected_operations" "text"[]) RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT CASE
      WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
      ELSE raw_operation
    END AS current_operation
    FROM current_operation
  )
  SELECT EXISTS (
    SELECT 1
    FROM normalized n
    CROSS JOIN LATERAL unnest(expected_operations) AS expected_operation
    WHERE expected_operation IS NOT NULL
      AND expected_operation <> ''
      AND n.current_operation = CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END
  );
$$;


ALTER FUNCTION "storage"."allow_any_operation"("expected_operations" "text"[]) OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."allow_only_operation"("expected_operation" "text") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT
      CASE
        WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
        ELSE raw_operation
      END AS current_operation,
      CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END AS requested_operation
    FROM current_operation
  )
  SELECT CASE
    WHEN requested_operation IS NULL OR requested_operation = '' THEN FALSE
    ELSE COALESCE(current_operation = requested_operation, FALSE)
  END
  FROM normalized;
$$;


ALTER FUNCTION "storage"."allow_only_operation"("expected_operation" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


ALTER FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."enforce_bucket_name_length"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


ALTER FUNCTION "storage"."enforce_bucket_name_length"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."extension"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
_parts text[];
_filename text;
BEGIN
	select string_to_array(name, '/') into _parts;
	select _parts[array_length(_parts,1)] into _filename;
	-- @todo return the last part instead of 2
	return reverse(split_part(reverse(_filename), '.', 1));
END
$$;


ALTER FUNCTION "storage"."extension"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."filename"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


ALTER FUNCTION "storage"."filename"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."foldername"("name" "text") RETURNS "text"[]
    LANGUAGE "plpgsql"
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[1:array_length(_parts,1)-1];
END
$$;


ALTER FUNCTION "storage"."foldername"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_common_prefix"("p_key" "text", "p_prefix" "text", "p_delimiter" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
SELECT CASE
    WHEN position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)) > 0
    THEN left(p_key, length(p_prefix) + position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)))
    ELSE NULL
END;
$$;


ALTER FUNCTION "storage"."get_common_prefix"("p_key" "text", "p_prefix" "text", "p_delimiter" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_size_by_bucket"() RETURNS TABLE("size" bigint, "bucket_id" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::int) as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


ALTER FUNCTION "storage"."get_size_by_bucket"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "next_key_token" "text" DEFAULT ''::"text", "next_upload_token" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "id" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


ALTER FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "next_key_token" "text", "next_upload_token" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_objects_with_delimiter"("_bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "start_after" "text" DEFAULT ''::"text", "next_token" "text" DEFAULT ''::"text", "sort_order" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "metadata" "jsonb", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;

    -- Configuration
    v_is_asc BOOLEAN;
    v_prefix TEXT;
    v_start TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_is_asc := lower(coalesce(sort_order, 'asc')) = 'asc';
    v_prefix := coalesce(prefix_param, '');
    v_start := CASE WHEN coalesce(next_token, '') <> '' THEN next_token ELSE coalesce(start_after, '') END;
    v_file_batch_size := LEAST(GREATEST(max_keys * 2, 100), 1000);

    -- Calculate upper bound for prefix filtering (bytewise, using COLLATE "C")
    IF v_prefix = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix, 1) = delimiter_param THEN
        v_upper_bound := left(v_prefix, -1) || chr(ascii(delimiter_param) + 1);
    ELSE
        v_upper_bound := left(v_prefix, -1) || chr(ascii(right(v_prefix, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'AND o.name COLLATE "C" < $3 ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'AND o.name COLLATE "C" >= $3 ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- ========================================================================
    -- SEEK INITIALIZATION: Determine starting position
    -- ========================================================================
    IF v_start = '' THEN
        IF v_is_asc THEN
            v_next_seek := v_prefix;
        ELSE
            -- DESC without cursor: find the last item in range
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;

            IF v_next_seek IS NOT NULL THEN
                v_next_seek := v_next_seek || delimiter_param;
            ELSE
                RETURN;
            END IF;
        END IF;
    ELSE
        -- Cursor provided: determine if it refers to a folder or leaf
        IF EXISTS (
            SELECT 1 FROM storage.objects o
            WHERE o.bucket_id = _bucket_id
              AND o.name COLLATE "C" LIKE v_start || delimiter_param || '%'
            LIMIT 1
        ) THEN
            -- Cursor refers to a folder
            IF v_is_asc THEN
                v_next_seek := v_start || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_start || delimiter_param;
            END IF;
        ELSE
            -- Cursor refers to a leaf object
            IF v_is_asc THEN
                v_next_seek := v_start || delimiter_param;
            ELSE
                v_next_seek := v_start;
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= max_keys;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(v_peek_name, v_prefix, delimiter_param);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Emit and skip to next folder (no heap access needed)
            name := rtrim(v_common_prefix, delimiter_param);
            id := NULL;
            updated_at := NULL;
            created_at := NULL;
            last_accessed_at := NULL;
            metadata := NULL;
            RETURN NEXT;
            v_count := v_count + 1;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := left(v_common_prefix, -1) || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_common_prefix;
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query USING _bucket_id, v_next_seek,
                CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(v_current.name, v_prefix, delimiter_param);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := v_current.name;
                    EXIT;
                END IF;

                -- Emit file
                name := v_current.name;
                id := v_current.id;
                updated_at := v_current.updated_at;
                created_at := v_current.created_at;
                last_accessed_at := v_current.last_accessed_at;
                metadata := v_current.metadata;
                RETURN NEXT;
                v_count := v_count + 1;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := v_current.name || delimiter_param;
                ELSE
                    v_next_seek := v_current.name;
                END IF;

                EXIT WHEN v_count >= max_keys;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION "storage"."list_objects_with_delimiter"("_bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "start_after" "text", "next_token" "text", "sort_order" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."operation"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


ALTER FUNCTION "storage"."operation"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."protect_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Check if storage.allow_delete_query is set to 'true'
    IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
        RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
            USING HINT = 'This prevents accidental data loss from orphaned objects.',
                  ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION "storage"."protect_delete"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;
    v_delimiter CONSTANT TEXT := '/';

    -- Configuration
    v_limit INT;
    v_prefix TEXT;
    v_prefix_lower TEXT;
    v_is_asc BOOLEAN;
    v_order_by TEXT;
    v_sort_order TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;
    v_skipped INT := 0;
BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_limit := LEAST(coalesce(limits, 100), 1500);
    v_prefix := coalesce(prefix, '') || coalesce(search, '');
    v_prefix_lower := lower(v_prefix);
    v_is_asc := lower(coalesce(sortorder, 'asc')) = 'asc';
    v_file_batch_size := LEAST(GREATEST(v_limit * 2, 100), 1000);

    -- Validate sort column
    CASE lower(coalesce(sortcolumn, 'name'))
        WHEN 'name' THEN v_order_by := 'name';
        WHEN 'updated_at' THEN v_order_by := 'updated_at';
        WHEN 'created_at' THEN v_order_by := 'created_at';
        WHEN 'last_accessed_at' THEN v_order_by := 'last_accessed_at';
        ELSE v_order_by := 'name';
    END CASE;

    v_sort_order := CASE WHEN v_is_asc THEN 'asc' ELSE 'desc' END;

    -- ========================================================================
    -- NON-NAME SORTING: Use path_tokens approach (unchanged)
    -- ========================================================================
    IF v_order_by != 'name' THEN
        RETURN QUERY EXECUTE format(
            $sql$
            WITH folders AS (
                SELECT path_tokens[$1] AS folder
                FROM storage.objects
                WHERE objects.name ILIKE $2 || '%%'
                  AND bucket_id = $3
                  AND array_length(objects.path_tokens, 1) <> $1
                GROUP BY folder
                ORDER BY folder %s
            )
            (SELECT folder AS "name",
                   NULL::uuid AS id,
                   NULL::timestamptz AS updated_at,
                   NULL::timestamptz AS created_at,
                   NULL::timestamptz AS last_accessed_at,
                   NULL::jsonb AS metadata FROM folders)
            UNION ALL
            (SELECT path_tokens[$1] AS "name",
                   id, updated_at, created_at, last_accessed_at, metadata
             FROM storage.objects
             WHERE objects.name ILIKE $2 || '%%'
               AND bucket_id = $3
               AND array_length(objects.path_tokens, 1) = $1
             ORDER BY %I %s)
            LIMIT $4 OFFSET $5
            $sql$, v_sort_order, v_order_by, v_sort_order
        ) USING levels, v_prefix, bucketname, v_limit, offsets;
        RETURN;
    END IF;

    -- ========================================================================
    -- NAME SORTING: Hybrid skip-scan with batch optimization
    -- ========================================================================

    -- Calculate upper bound for prefix filtering
    IF v_prefix_lower = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix_lower, 1) = v_delimiter THEN
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(v_delimiter) + 1);
    ELSE
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(right(v_prefix_lower, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'AND lower(o.name) COLLATE "C" < $3 ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'AND lower(o.name) COLLATE "C" >= $3 ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- Initialize seek position
    IF v_is_asc THEN
        v_next_seek := v_prefix_lower;
    ELSE
        -- DESC: find the last item in range first (static SQL)
        IF v_upper_bound IS NOT NULL THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower AND lower(o.name) COLLATE "C" < v_upper_bound
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSIF v_prefix_lower <> '' THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSE
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        END IF;

        IF v_peek_name IS NOT NULL THEN
            v_next_seek := lower(v_peek_name) || v_delimiter;
        ELSE
            RETURN;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= v_limit;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix_lower <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(lower(v_peek_name), v_prefix_lower, v_delimiter);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Handle offset, emit if needed, skip to next folder
            IF v_skipped < offsets THEN
                v_skipped := v_skipped + 1;
            ELSE
                name := split_part(rtrim(storage.get_common_prefix(v_peek_name, v_prefix, v_delimiter), v_delimiter), v_delimiter, levels);
                id := NULL;
                updated_at := NULL;
                created_at := NULL;
                last_accessed_at := NULL;
                metadata := NULL;
                RETURN NEXT;
                v_count := v_count + 1;
            END IF;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := lower(left(v_common_prefix, -1)) || chr(ascii(v_delimiter) + 1);
            ELSE
                v_next_seek := lower(v_common_prefix);
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix_lower is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(lower(v_current.name), v_prefix_lower, v_delimiter);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := lower(v_current.name);
                    EXIT;
                END IF;

                -- Handle offset skipping
                IF v_skipped < offsets THEN
                    v_skipped := v_skipped + 1;
                ELSE
                    -- Emit file
                    name := split_part(v_current.name, v_delimiter, levels);
                    id := v_current.id;
                    updated_at := v_current.updated_at;
                    created_at := v_current.created_at;
                    last_accessed_at := v_current.last_accessed_at;
                    metadata := v_current.metadata;
                    RETURN NEXT;
                    v_count := v_count + 1;
                END IF;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := lower(v_current.name) || v_delimiter;
                ELSE
                    v_next_seek := lower(v_current.name);
                END IF;

                EXIT WHEN v_count >= v_limit;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_by_timestamp"("p_prefix" "text", "p_bucket_id" "text", "p_limit" integer, "p_level" integer, "p_start_after" "text", "p_sort_order" "text", "p_sort_column" "text", "p_sort_column_after" "text") RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_cursor_op text;
    v_query text;
    v_prefix text;
BEGIN
    v_prefix := coalesce(p_prefix, '');

    IF p_sort_order = 'asc' THEN
        v_cursor_op := '>';
    ELSE
        v_cursor_op := '<';
    END IF;

    v_query := format($sql$
        WITH raw_objects AS (
            SELECT
                o.name AS obj_name,
                o.id AS obj_id,
                o.updated_at AS obj_updated_at,
                o.created_at AS obj_created_at,
                o.last_accessed_at AS obj_last_accessed_at,
                o.metadata AS obj_metadata,
                storage.get_common_prefix(o.name, $1, '/') AS common_prefix
            FROM storage.objects o
            WHERE o.bucket_id = $2
              AND o.name COLLATE "C" LIKE $1 || '%%'
        ),
        -- Aggregate common prefixes (folders)
        -- Both created_at and updated_at use MIN(obj_created_at) to match the old prefixes table behavior
        aggregated_prefixes AS (
            SELECT
                rtrim(common_prefix, '/') AS name,
                NULL::uuid AS id,
                MIN(obj_created_at) AS updated_at,
                MIN(obj_created_at) AS created_at,
                NULL::timestamptz AS last_accessed_at,
                NULL::jsonb AS metadata,
                TRUE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NOT NULL
            GROUP BY common_prefix
        ),
        leaf_objects AS (
            SELECT
                obj_name AS name,
                obj_id AS id,
                obj_updated_at AS updated_at,
                obj_created_at AS created_at,
                obj_last_accessed_at AS last_accessed_at,
                obj_metadata AS metadata,
                FALSE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NULL
        ),
        combined AS (
            SELECT * FROM aggregated_prefixes
            UNION ALL
            SELECT * FROM leaf_objects
        ),
        filtered AS (
            SELECT *
            FROM combined
            WHERE (
                $5 = ''
                OR ROW(
                    date_trunc('milliseconds', %I),
                    name COLLATE "C"
                ) %s ROW(
                    COALESCE(NULLIF($6, '')::timestamptz, 'epoch'::timestamptz),
                    $5
                )
            )
        )
        SELECT
            split_part(name, '/', $3) AS key,
            name,
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
        FROM filtered
        ORDER BY
            COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz) %s,
            name COLLATE "C" %s
        LIMIT $4
    $sql$,
        p_sort_column,
        v_cursor_op,
        p_sort_column,
        p_sort_order,
        p_sort_order
    );

    RETURN QUERY EXECUTE v_query
    USING v_prefix, p_bucket_id, p_level, p_limit, p_start_after, p_sort_column_after;
END;
$_$;


ALTER FUNCTION "storage"."search_by_timestamp"("p_prefix" "text", "p_bucket_id" "text", "p_limit" integer, "p_level" integer, "p_start_after" "text", "p_sort_order" "text", "p_sort_column" "text", "p_sort_column_after" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "start_after" "text" DEFAULT ''::"text", "sort_order" "text" DEFAULT 'asc'::"text", "sort_column" "text" DEFAULT 'name'::"text", "sort_column_after" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    v_sort_col text;
    v_sort_ord text;
    v_limit int;
BEGIN
    -- Cap limit to maximum of 1500 records
    v_limit := LEAST(coalesce(limits, 100), 1500);

    -- Validate and normalize sort_order
    v_sort_ord := lower(coalesce(sort_order, 'asc'));
    IF v_sort_ord NOT IN ('asc', 'desc') THEN
        v_sort_ord := 'asc';
    END IF;

    -- Validate and normalize sort_column
    v_sort_col := lower(coalesce(sort_column, 'name'));
    IF v_sort_col NOT IN ('name', 'updated_at', 'created_at') THEN
        v_sort_col := 'name';
    END IF;

    -- Route to appropriate implementation
    IF v_sort_col = 'name' THEN
        -- Use list_objects_with_delimiter for name sorting (most efficient: O(k * log n))
        RETURN QUERY
        SELECT
            split_part(l.name, '/', levels) AS key,
            l.name AS name,
            l.id,
            l.updated_at,
            l.created_at,
            l.last_accessed_at,
            l.metadata
        FROM storage.list_objects_with_delimiter(
            bucket_name,
            coalesce(prefix, ''),
            '/',
            v_limit,
            start_after,
            '',
            v_sort_ord
        ) l;
    ELSE
        -- Use aggregation approach for timestamp sorting
        -- Not efficient for large datasets but supports correct pagination
        RETURN QUERY SELECT * FROM storage.search_by_timestamp(
            prefix, bucket_name, v_limit, levels, start_after,
            v_sort_ord, v_sort_col, sort_column_after
        );
    END IF;
END;
$$;


ALTER FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer, "levels" integer, "start_after" "text", "sort_order" "text", "sort_column" "text", "sort_column_after" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


ALTER FUNCTION "storage"."update_updated_at_column"() OWNER TO "supabase_storage_admin";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "auth"."audit_log_entries" (
    "instance_id" "uuid",
    "id" "uuid" NOT NULL,
    "payload" json,
    "created_at" timestamp with time zone,
    "ip_address" character varying(64) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE "auth"."audit_log_entries" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."audit_log_entries" IS 'Auth: Audit trail for user actions.';



CREATE TABLE IF NOT EXISTS "auth"."custom_oauth_providers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "provider_type" "text" NOT NULL,
    "identifier" "text" NOT NULL,
    "name" "text" NOT NULL,
    "client_id" "text" NOT NULL,
    "client_secret" "text" NOT NULL,
    "acceptable_client_ids" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "scopes" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "pkce_enabled" boolean DEFAULT true NOT NULL,
    "attribute_mapping" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "authorization_params" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "email_optional" boolean DEFAULT false NOT NULL,
    "issuer" "text",
    "discovery_url" "text",
    "skip_nonce_check" boolean DEFAULT false NOT NULL,
    "cached_discovery" "jsonb",
    "discovery_cached_at" timestamp with time zone,
    "authorization_url" "text",
    "token_url" "text",
    "userinfo_url" "text",
    "jwks_uri" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "custom_oauth_providers_authorization_url_https" CHECK ((("authorization_url" IS NULL) OR ("authorization_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_authorization_url_length" CHECK ((("authorization_url" IS NULL) OR ("char_length"("authorization_url") <= 2048))),
    CONSTRAINT "custom_oauth_providers_client_id_length" CHECK ((("char_length"("client_id") >= 1) AND ("char_length"("client_id") <= 512))),
    CONSTRAINT "custom_oauth_providers_discovery_url_length" CHECK ((("discovery_url" IS NULL) OR ("char_length"("discovery_url") <= 2048))),
    CONSTRAINT "custom_oauth_providers_identifier_format" CHECK (("identifier" ~ '^[a-z0-9][a-z0-9:-]{0,48}[a-z0-9]$'::"text")),
    CONSTRAINT "custom_oauth_providers_issuer_length" CHECK ((("issuer" IS NULL) OR (("char_length"("issuer") >= 1) AND ("char_length"("issuer") <= 2048)))),
    CONSTRAINT "custom_oauth_providers_jwks_uri_https" CHECK ((("jwks_uri" IS NULL) OR ("jwks_uri" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_jwks_uri_length" CHECK ((("jwks_uri" IS NULL) OR ("char_length"("jwks_uri") <= 2048))),
    CONSTRAINT "custom_oauth_providers_name_length" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 100))),
    CONSTRAINT "custom_oauth_providers_oauth2_requires_endpoints" CHECK ((("provider_type" <> 'oauth2'::"text") OR (("authorization_url" IS NOT NULL) AND ("token_url" IS NOT NULL) AND ("userinfo_url" IS NOT NULL)))),
    CONSTRAINT "custom_oauth_providers_oidc_discovery_url_https" CHECK ((("provider_type" <> 'oidc'::"text") OR ("discovery_url" IS NULL) OR ("discovery_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_oidc_issuer_https" CHECK ((("provider_type" <> 'oidc'::"text") OR ("issuer" IS NULL) OR ("issuer" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_oidc_requires_issuer" CHECK ((("provider_type" <> 'oidc'::"text") OR ("issuer" IS NOT NULL))),
    CONSTRAINT "custom_oauth_providers_provider_type_check" CHECK (("provider_type" = ANY (ARRAY['oauth2'::"text", 'oidc'::"text"]))),
    CONSTRAINT "custom_oauth_providers_token_url_https" CHECK ((("token_url" IS NULL) OR ("token_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_token_url_length" CHECK ((("token_url" IS NULL) OR ("char_length"("token_url") <= 2048))),
    CONSTRAINT "custom_oauth_providers_userinfo_url_https" CHECK ((("userinfo_url" IS NULL) OR ("userinfo_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_userinfo_url_length" CHECK ((("userinfo_url" IS NULL) OR ("char_length"("userinfo_url") <= 2048)))
);


ALTER TABLE "auth"."custom_oauth_providers" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."flow_state" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid",
    "auth_code" "text",
    "code_challenge_method" "auth"."code_challenge_method",
    "code_challenge" "text",
    "provider_type" "text" NOT NULL,
    "provider_access_token" "text",
    "provider_refresh_token" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "authentication_method" "text" NOT NULL,
    "auth_code_issued_at" timestamp with time zone,
    "invite_token" "text",
    "referrer" "text",
    "oauth_client_state_id" "uuid",
    "linking_target_id" "uuid",
    "email_optional" boolean DEFAULT false NOT NULL
);


ALTER TABLE "auth"."flow_state" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."flow_state" IS 'Stores metadata for all OAuth/SSO login flows';



CREATE TABLE IF NOT EXISTS "auth"."identities" (
    "provider_id" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "identity_data" "jsonb" NOT NULL,
    "provider" "text" NOT NULL,
    "last_sign_in_at" timestamp with time zone,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "email" "text" GENERATED ALWAYS AS ("lower"(("identity_data" ->> 'email'::"text"))) STORED,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);


ALTER TABLE "auth"."identities" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."identities" IS 'Auth: Stores identities associated to a user.';



COMMENT ON COLUMN "auth"."identities"."email" IS 'Auth: Email is a generated column that references the optional email property in the identity_data';



CREATE TABLE IF NOT EXISTS "auth"."instances" (
    "id" "uuid" NOT NULL,
    "uuid" "uuid",
    "raw_base_config" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
);


ALTER TABLE "auth"."instances" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."instances" IS 'Auth: Manages users across multiple sites.';



CREATE TABLE IF NOT EXISTS "auth"."mfa_amr_claims" (
    "session_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "authentication_method" "text" NOT NULL,
    "id" "uuid" NOT NULL
);


ALTER TABLE "auth"."mfa_amr_claims" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_amr_claims" IS 'auth: stores authenticator method reference claims for multi factor authentication';



CREATE TABLE IF NOT EXISTS "auth"."mfa_challenges" (
    "id" "uuid" NOT NULL,
    "factor_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "verified_at" timestamp with time zone,
    "ip_address" "inet" NOT NULL,
    "otp_code" "text",
    "web_authn_session_data" "jsonb"
);


ALTER TABLE "auth"."mfa_challenges" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_challenges" IS 'auth: stores metadata about challenge requests made';



CREATE TABLE IF NOT EXISTS "auth"."mfa_factors" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "friendly_name" "text",
    "factor_type" "auth"."factor_type" NOT NULL,
    "status" "auth"."factor_status" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "secret" "text",
    "phone" "text",
    "last_challenged_at" timestamp with time zone,
    "web_authn_credential" "jsonb",
    "web_authn_aaguid" "uuid",
    "last_webauthn_challenge_data" "jsonb"
);


ALTER TABLE "auth"."mfa_factors" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_factors" IS 'auth: stores metadata about factors';



COMMENT ON COLUMN "auth"."mfa_factors"."last_webauthn_challenge_data" IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';



CREATE TABLE IF NOT EXISTS "auth"."oauth_authorizations" (
    "id" "uuid" NOT NULL,
    "authorization_id" "text" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "redirect_uri" "text" NOT NULL,
    "scope" "text" NOT NULL,
    "state" "text",
    "resource" "text",
    "code_challenge" "text",
    "code_challenge_method" "auth"."code_challenge_method",
    "response_type" "auth"."oauth_response_type" DEFAULT 'code'::"auth"."oauth_response_type" NOT NULL,
    "status" "auth"."oauth_authorization_status" DEFAULT 'pending'::"auth"."oauth_authorization_status" NOT NULL,
    "authorization_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '00:03:00'::interval) NOT NULL,
    "approved_at" timestamp with time zone,
    "nonce" "text",
    CONSTRAINT "oauth_authorizations_authorization_code_length" CHECK (("char_length"("authorization_code") <= 255)),
    CONSTRAINT "oauth_authorizations_code_challenge_length" CHECK (("char_length"("code_challenge") <= 128)),
    CONSTRAINT "oauth_authorizations_expires_at_future" CHECK (("expires_at" > "created_at")),
    CONSTRAINT "oauth_authorizations_nonce_length" CHECK (("char_length"("nonce") <= 255)),
    CONSTRAINT "oauth_authorizations_redirect_uri_length" CHECK (("char_length"("redirect_uri") <= 2048)),
    CONSTRAINT "oauth_authorizations_resource_length" CHECK (("char_length"("resource") <= 2048)),
    CONSTRAINT "oauth_authorizations_scope_length" CHECK (("char_length"("scope") <= 4096)),
    CONSTRAINT "oauth_authorizations_state_length" CHECK (("char_length"("state") <= 4096))
);


ALTER TABLE "auth"."oauth_authorizations" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."oauth_client_states" (
    "id" "uuid" NOT NULL,
    "provider_type" "text" NOT NULL,
    "code_verifier" "text",
    "created_at" timestamp with time zone NOT NULL
);


ALTER TABLE "auth"."oauth_client_states" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."oauth_client_states" IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';



CREATE TABLE IF NOT EXISTS "auth"."oauth_clients" (
    "id" "uuid" NOT NULL,
    "client_secret_hash" "text",
    "registration_type" "auth"."oauth_registration_type" NOT NULL,
    "redirect_uris" "text" NOT NULL,
    "grant_types" "text" NOT NULL,
    "client_name" "text",
    "client_uri" "text",
    "logo_uri" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "client_type" "auth"."oauth_client_type" DEFAULT 'confidential'::"auth"."oauth_client_type" NOT NULL,
    "token_endpoint_auth_method" "text" NOT NULL,
    CONSTRAINT "oauth_clients_client_name_length" CHECK (("char_length"("client_name") <= 1024)),
    CONSTRAINT "oauth_clients_client_uri_length" CHECK (("char_length"("client_uri") <= 2048)),
    CONSTRAINT "oauth_clients_logo_uri_length" CHECK (("char_length"("logo_uri") <= 2048)),
    CONSTRAINT "oauth_clients_token_endpoint_auth_method_check" CHECK (("token_endpoint_auth_method" = ANY (ARRAY['client_secret_basic'::"text", 'client_secret_post'::"text", 'none'::"text"])))
);


ALTER TABLE "auth"."oauth_clients" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."oauth_consents" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "scopes" "text" NOT NULL,
    "granted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revoked_at" timestamp with time zone,
    CONSTRAINT "oauth_consents_revoked_after_granted" CHECK ((("revoked_at" IS NULL) OR ("revoked_at" >= "granted_at"))),
    CONSTRAINT "oauth_consents_scopes_length" CHECK (("char_length"("scopes") <= 2048)),
    CONSTRAINT "oauth_consents_scopes_not_empty" CHECK (("char_length"(TRIM(BOTH FROM "scopes")) > 0))
);


ALTER TABLE "auth"."oauth_consents" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."one_time_tokens" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "token_type" "auth"."one_time_token_type" NOT NULL,
    "token_hash" "text" NOT NULL,
    "relates_to" "text" NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "one_time_tokens_token_hash_check" CHECK (("char_length"("token_hash") > 0))
);


ALTER TABLE "auth"."one_time_tokens" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."refresh_tokens" (
    "instance_id" "uuid",
    "id" bigint NOT NULL,
    "token" character varying(255),
    "user_id" character varying(255),
    "revoked" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "parent" character varying(255),
    "session_id" "uuid"
);


ALTER TABLE "auth"."refresh_tokens" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."refresh_tokens" IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';



CREATE SEQUENCE IF NOT EXISTS "auth"."refresh_tokens_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "auth"."refresh_tokens_id_seq" OWNER TO "supabase_auth_admin";


ALTER SEQUENCE "auth"."refresh_tokens_id_seq" OWNED BY "auth"."refresh_tokens"."id";



CREATE TABLE IF NOT EXISTS "auth"."saml_providers" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "entity_id" "text" NOT NULL,
    "metadata_xml" "text" NOT NULL,
    "metadata_url" "text",
    "attribute_mapping" "jsonb",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "name_id_format" "text",
    CONSTRAINT "entity_id not empty" CHECK (("char_length"("entity_id") > 0)),
    CONSTRAINT "metadata_url not empty" CHECK ((("metadata_url" = NULL::"text") OR ("char_length"("metadata_url") > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK (("char_length"("metadata_xml") > 0))
);


ALTER TABLE "auth"."saml_providers" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."saml_providers" IS 'Auth: Manages SAML Identity Provider connections.';



CREATE TABLE IF NOT EXISTS "auth"."saml_relay_states" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "request_id" "text" NOT NULL,
    "for_email" "text",
    "redirect_to" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "flow_state_id" "uuid",
    CONSTRAINT "request_id not empty" CHECK (("char_length"("request_id") > 0))
);


ALTER TABLE "auth"."saml_relay_states" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."saml_relay_states" IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';



CREATE TABLE IF NOT EXISTS "auth"."schema_migrations" (
    "version" character varying(255) NOT NULL
);


ALTER TABLE "auth"."schema_migrations" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."schema_migrations" IS 'Auth: Manages updates to the auth system.';



CREATE TABLE IF NOT EXISTS "auth"."sessions" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "factor_id" "uuid",
    "aal" "auth"."aal_level",
    "not_after" timestamp with time zone,
    "refreshed_at" timestamp without time zone,
    "user_agent" "text",
    "ip" "inet",
    "tag" "text",
    "oauth_client_id" "uuid",
    "refresh_token_hmac_key" "text",
    "refresh_token_counter" bigint,
    "scopes" "text",
    CONSTRAINT "sessions_scopes_length" CHECK (("char_length"("scopes") <= 4096))
);


ALTER TABLE "auth"."sessions" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sessions" IS 'Auth: Stores session data associated to a user.';



COMMENT ON COLUMN "auth"."sessions"."not_after" IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';



COMMENT ON COLUMN "auth"."sessions"."refresh_token_hmac_key" IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';



COMMENT ON COLUMN "auth"."sessions"."refresh_token_counter" IS 'Holds the ID (counter) of the last issued refresh token.';



CREATE TABLE IF NOT EXISTS "auth"."sso_domains" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "domain" "text" NOT NULL,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK (("char_length"("domain") > 0))
);


ALTER TABLE "auth"."sso_domains" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sso_domains" IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';



CREATE TABLE IF NOT EXISTS "auth"."sso_providers" (
    "id" "uuid" NOT NULL,
    "resource_id" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "disabled" boolean,
    CONSTRAINT "resource_id not empty" CHECK ((("resource_id" = NULL::"text") OR ("char_length"("resource_id") > 0)))
);


ALTER TABLE "auth"."sso_providers" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sso_providers" IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';



COMMENT ON COLUMN "auth"."sso_providers"."resource_id" IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';



CREATE TABLE IF NOT EXISTS "auth"."users" (
    "instance_id" "uuid",
    "id" "uuid" NOT NULL,
    "aud" character varying(255),
    "role" character varying(255),
    "email" character varying(255),
    "encrypted_password" character varying(255),
    "email_confirmed_at" timestamp with time zone,
    "invited_at" timestamp with time zone,
    "confirmation_token" character varying(255),
    "confirmation_sent_at" timestamp with time zone,
    "recovery_token" character varying(255),
    "recovery_sent_at" timestamp with time zone,
    "email_change_token_new" character varying(255),
    "email_change" character varying(255),
    "email_change_sent_at" timestamp with time zone,
    "last_sign_in_at" timestamp with time zone,
    "raw_app_meta_data" "jsonb",
    "raw_user_meta_data" "jsonb",
    "is_super_admin" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "phone" "text" DEFAULT NULL::character varying,
    "phone_confirmed_at" timestamp with time zone,
    "phone_change" "text" DEFAULT ''::character varying,
    "phone_change_token" character varying(255) DEFAULT ''::character varying,
    "phone_change_sent_at" timestamp with time zone,
    "confirmed_at" timestamp with time zone GENERATED ALWAYS AS (LEAST("email_confirmed_at", "phone_confirmed_at")) STORED,
    "email_change_token_current" character varying(255) DEFAULT ''::character varying,
    "email_change_confirm_status" smallint DEFAULT 0,
    "banned_until" timestamp with time zone,
    "reauthentication_token" character varying(255) DEFAULT ''::character varying,
    "reauthentication_sent_at" timestamp with time zone,
    "is_sso_user" boolean DEFAULT false NOT NULL,
    "deleted_at" timestamp with time zone,
    "is_anonymous" boolean DEFAULT false NOT NULL,
    CONSTRAINT "users_email_change_confirm_status_check" CHECK ((("email_change_confirm_status" >= 0) AND ("email_change_confirm_status" <= 2)))
);


ALTER TABLE "auth"."users" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."users" IS 'Auth: Stores user login data within a secure schema.';



COMMENT ON COLUMN "auth"."users"."is_sso_user" IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';



CREATE TABLE IF NOT EXISTS "auth"."webauthn_challenges" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "challenge_type" "text" NOT NULL,
    "session_data" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    CONSTRAINT "webauthn_challenges_challenge_type_check" CHECK (("challenge_type" = ANY (ARRAY['signup'::"text", 'registration'::"text", 'authentication'::"text"])))
);


ALTER TABLE "auth"."webauthn_challenges" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."webauthn_credentials" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "credential_id" "bytea" NOT NULL,
    "public_key" "bytea" NOT NULL,
    "attestation_type" "text" DEFAULT ''::"text" NOT NULL,
    "aaguid" "uuid",
    "sign_count" bigint DEFAULT 0 NOT NULL,
    "transports" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "backup_eligible" boolean DEFAULT false NOT NULL,
    "backed_up" boolean DEFAULT false NOT NULL,
    "friendly_name" "text" DEFAULT ''::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_used_at" timestamp with time zone
);


ALTER TABLE "auth"."webauthn_credentials" OWNER TO "supabase_auth_admin";


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


CREATE TABLE IF NOT EXISTS "storage"."buckets" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "public" boolean DEFAULT false,
    "avif_autodetection" boolean DEFAULT false,
    "file_size_limit" bigint,
    "allowed_mime_types" "text"[],
    "owner_id" "text",
    "type" "storage"."buckettype" DEFAULT 'STANDARD'::"storage"."buckettype" NOT NULL
);


ALTER TABLE "storage"."buckets" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."buckets"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."buckets_analytics" (
    "name" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'ANALYTICS'::"storage"."buckettype" NOT NULL,
    "format" "text" DEFAULT 'ICEBERG'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "storage"."buckets_analytics" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."buckets_vectors" (
    "id" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'VECTOR'::"storage"."buckettype" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."buckets_vectors" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."migrations" (
    "id" integer NOT NULL,
    "name" character varying(100) NOT NULL,
    "hash" character varying(40) NOT NULL,
    "executed_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "storage"."migrations" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."objects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bucket_id" "text",
    "name" "text",
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_accessed_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb",
    "path_tokens" "text"[] GENERATED ALWAYS AS ("string_to_array"("name", '/'::"text")) STORED,
    "version" "text",
    "owner_id" "text",
    "user_metadata" "jsonb"
);


ALTER TABLE "storage"."objects" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."objects"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads" (
    "id" "text" NOT NULL,
    "in_progress_size" bigint DEFAULT 0 NOT NULL,
    "upload_signature" "text" NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "version" "text" NOT NULL,
    "owner_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_metadata" "jsonb",
    "metadata" "jsonb"
);


ALTER TABLE "storage"."s3_multipart_uploads" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads_parts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "upload_id" "text" NOT NULL,
    "size" bigint DEFAULT 0 NOT NULL,
    "part_number" integer NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "etag" "text" NOT NULL,
    "owner_id" "text",
    "version" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."s3_multipart_uploads_parts" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."vector_indexes" (
    "id" "text" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL COLLATE "pg_catalog"."C",
    "bucket_id" "text" NOT NULL,
    "data_type" "text" NOT NULL,
    "dimension" integer NOT NULL,
    "distance_metric" "text" NOT NULL,
    "metadata_configuration" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."vector_indexes" OWNER TO "supabase_storage_admin";


ALTER TABLE ONLY "auth"."refresh_tokens" ALTER COLUMN "id" SET DEFAULT "nextval"('"auth"."refresh_tokens_id_seq"'::"regclass");



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "amr_id_pk" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."audit_log_entries"
    ADD CONSTRAINT "audit_log_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."custom_oauth_providers"
    ADD CONSTRAINT "custom_oauth_providers_identifier_key" UNIQUE ("identifier");



ALTER TABLE ONLY "auth"."custom_oauth_providers"
    ADD CONSTRAINT "custom_oauth_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."flow_state"
    ADD CONSTRAINT "flow_state_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_provider_id_provider_unique" UNIQUE ("provider_id", "provider");



ALTER TABLE ONLY "auth"."instances"
    ADD CONSTRAINT "instances_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "mfa_amr_claims_session_id_authentication_method_pkey" UNIQUE ("session_id", "authentication_method");



ALTER TABLE ONLY "auth"."mfa_challenges"
    ADD CONSTRAINT "mfa_challenges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_last_challenged_at_key" UNIQUE ("last_challenged_at");



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_authorization_code_key" UNIQUE ("authorization_code");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_authorization_id_key" UNIQUE ("authorization_id");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_client_states"
    ADD CONSTRAINT "oauth_client_states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_clients"
    ADD CONSTRAINT "oauth_clients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_user_client_unique" UNIQUE ("user_id", "client_id");



ALTER TABLE ONLY "auth"."one_time_tokens"
    ADD CONSTRAINT "one_time_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_token_unique" UNIQUE ("token");



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_entity_id_key" UNIQUE ("entity_id");



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."schema_migrations"
    ADD CONSTRAINT "schema_migrations_pkey" PRIMARY KEY ("version");



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."sso_domains"
    ADD CONSTRAINT "sso_domains_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."sso_providers"
    ADD CONSTRAINT "sso_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."users"
    ADD CONSTRAINT "users_phone_key" UNIQUE ("phone");



ALTER TABLE ONLY "auth"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."webauthn_challenges"
    ADD CONSTRAINT "webauthn_challenges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."webauthn_credentials"
    ADD CONSTRAINT "webauthn_credentials_pkey" PRIMARY KEY ("id");



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



ALTER TABLE ONLY "storage"."buckets_analytics"
    ADD CONSTRAINT "buckets_analytics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets"
    ADD CONSTRAINT "buckets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets_vectors"
    ADD CONSTRAINT "buckets_vectors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_name_key" UNIQUE ("name");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."vector_indexes"
    ADD CONSTRAINT "vector_indexes_pkey" PRIMARY KEY ("id");



CREATE INDEX "audit_logs_instance_id_idx" ON "auth"."audit_log_entries" USING "btree" ("instance_id");



CREATE UNIQUE INDEX "confirmation_token_idx" ON "auth"."users" USING "btree" ("confirmation_token") WHERE (("confirmation_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "custom_oauth_providers_created_at_idx" ON "auth"."custom_oauth_providers" USING "btree" ("created_at");



CREATE INDEX "custom_oauth_providers_enabled_idx" ON "auth"."custom_oauth_providers" USING "btree" ("enabled");



CREATE INDEX "custom_oauth_providers_identifier_idx" ON "auth"."custom_oauth_providers" USING "btree" ("identifier");



CREATE INDEX "custom_oauth_providers_provider_type_idx" ON "auth"."custom_oauth_providers" USING "btree" ("provider_type");



CREATE UNIQUE INDEX "email_change_token_current_idx" ON "auth"."users" USING "btree" ("email_change_token_current") WHERE (("email_change_token_current")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "email_change_token_new_idx" ON "auth"."users" USING "btree" ("email_change_token_new") WHERE (("email_change_token_new")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "factor_id_created_at_idx" ON "auth"."mfa_factors" USING "btree" ("user_id", "created_at");



CREATE INDEX "flow_state_created_at_idx" ON "auth"."flow_state" USING "btree" ("created_at" DESC);



CREATE INDEX "identities_email_idx" ON "auth"."identities" USING "btree" ("email" "text_pattern_ops");



COMMENT ON INDEX "auth"."identities_email_idx" IS 'Auth: Ensures indexed queries on the email column';



CREATE INDEX "identities_user_id_idx" ON "auth"."identities" USING "btree" ("user_id");



CREATE INDEX "idx_auth_code" ON "auth"."flow_state" USING "btree" ("auth_code");



CREATE INDEX "idx_oauth_client_states_created_at" ON "auth"."oauth_client_states" USING "btree" ("created_at");



CREATE INDEX "idx_user_id_auth_method" ON "auth"."flow_state" USING "btree" ("user_id", "authentication_method");



CREATE INDEX "idx_users_created_at_desc" ON "auth"."users" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_users_email" ON "auth"."users" USING "btree" ("email");



CREATE INDEX "idx_users_last_sign_in_at_desc" ON "auth"."users" USING "btree" ("last_sign_in_at" DESC);



CREATE INDEX "idx_users_name" ON "auth"."users" USING "btree" ((("raw_user_meta_data" ->> 'name'::"text"))) WHERE (("raw_user_meta_data" ->> 'name'::"text") IS NOT NULL);



CREATE INDEX "mfa_challenge_created_at_idx" ON "auth"."mfa_challenges" USING "btree" ("created_at" DESC);



CREATE UNIQUE INDEX "mfa_factors_user_friendly_name_unique" ON "auth"."mfa_factors" USING "btree" ("friendly_name", "user_id") WHERE (TRIM(BOTH FROM "friendly_name") <> ''::"text");



CREATE INDEX "mfa_factors_user_id_idx" ON "auth"."mfa_factors" USING "btree" ("user_id");



CREATE INDEX "oauth_auth_pending_exp_idx" ON "auth"."oauth_authorizations" USING "btree" ("expires_at") WHERE ("status" = 'pending'::"auth"."oauth_authorization_status");



CREATE INDEX "oauth_clients_deleted_at_idx" ON "auth"."oauth_clients" USING "btree" ("deleted_at");



CREATE INDEX "oauth_consents_active_client_idx" ON "auth"."oauth_consents" USING "btree" ("client_id") WHERE ("revoked_at" IS NULL);



CREATE INDEX "oauth_consents_active_user_client_idx" ON "auth"."oauth_consents" USING "btree" ("user_id", "client_id") WHERE ("revoked_at" IS NULL);



CREATE INDEX "oauth_consents_user_order_idx" ON "auth"."oauth_consents" USING "btree" ("user_id", "granted_at" DESC);



CREATE INDEX "one_time_tokens_relates_to_hash_idx" ON "auth"."one_time_tokens" USING "hash" ("relates_to");



CREATE INDEX "one_time_tokens_token_hash_hash_idx" ON "auth"."one_time_tokens" USING "hash" ("token_hash");



CREATE UNIQUE INDEX "one_time_tokens_user_id_token_type_key" ON "auth"."one_time_tokens" USING "btree" ("user_id", "token_type");



CREATE UNIQUE INDEX "reauthentication_token_idx" ON "auth"."users" USING "btree" ("reauthentication_token") WHERE (("reauthentication_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "recovery_token_idx" ON "auth"."users" USING "btree" ("recovery_token") WHERE (("recovery_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "refresh_tokens_instance_id_idx" ON "auth"."refresh_tokens" USING "btree" ("instance_id");



CREATE INDEX "refresh_tokens_instance_id_user_id_idx" ON "auth"."refresh_tokens" USING "btree" ("instance_id", "user_id");



CREATE INDEX "refresh_tokens_parent_idx" ON "auth"."refresh_tokens" USING "btree" ("parent");



CREATE INDEX "refresh_tokens_session_id_revoked_idx" ON "auth"."refresh_tokens" USING "btree" ("session_id", "revoked");



CREATE INDEX "refresh_tokens_updated_at_idx" ON "auth"."refresh_tokens" USING "btree" ("updated_at" DESC);



CREATE INDEX "saml_providers_sso_provider_id_idx" ON "auth"."saml_providers" USING "btree" ("sso_provider_id");



CREATE INDEX "saml_relay_states_created_at_idx" ON "auth"."saml_relay_states" USING "btree" ("created_at" DESC);



CREATE INDEX "saml_relay_states_for_email_idx" ON "auth"."saml_relay_states" USING "btree" ("for_email");



CREATE INDEX "saml_relay_states_sso_provider_id_idx" ON "auth"."saml_relay_states" USING "btree" ("sso_provider_id");



CREATE INDEX "sessions_not_after_idx" ON "auth"."sessions" USING "btree" ("not_after" DESC);



CREATE INDEX "sessions_oauth_client_id_idx" ON "auth"."sessions" USING "btree" ("oauth_client_id");



CREATE INDEX "sessions_user_id_idx" ON "auth"."sessions" USING "btree" ("user_id");



CREATE UNIQUE INDEX "sso_domains_domain_idx" ON "auth"."sso_domains" USING "btree" ("lower"("domain"));



CREATE INDEX "sso_domains_sso_provider_id_idx" ON "auth"."sso_domains" USING "btree" ("sso_provider_id");



CREATE UNIQUE INDEX "sso_providers_resource_id_idx" ON "auth"."sso_providers" USING "btree" ("lower"("resource_id"));



CREATE INDEX "sso_providers_resource_id_pattern_idx" ON "auth"."sso_providers" USING "btree" ("resource_id" "text_pattern_ops");



CREATE UNIQUE INDEX "unique_phone_factor_per_user" ON "auth"."mfa_factors" USING "btree" ("user_id", "phone");



CREATE INDEX "user_id_created_at_idx" ON "auth"."sessions" USING "btree" ("user_id", "created_at");



CREATE UNIQUE INDEX "users_email_partial_key" ON "auth"."users" USING "btree" ("email") WHERE ("is_sso_user" = false);



COMMENT ON INDEX "auth"."users_email_partial_key" IS 'Auth: A partial unique index that applies only when is_sso_user is false';



CREATE INDEX "users_instance_id_email_idx" ON "auth"."users" USING "btree" ("instance_id", "lower"(("email")::"text"));



CREATE INDEX "users_instance_id_idx" ON "auth"."users" USING "btree" ("instance_id");



CREATE INDEX "users_is_anonymous_idx" ON "auth"."users" USING "btree" ("is_anonymous");



CREATE INDEX "webauthn_challenges_expires_at_idx" ON "auth"."webauthn_challenges" USING "btree" ("expires_at");



CREATE INDEX "webauthn_challenges_user_id_idx" ON "auth"."webauthn_challenges" USING "btree" ("user_id");



CREATE UNIQUE INDEX "webauthn_credentials_credential_id_key" ON "auth"."webauthn_credentials" USING "btree" ("credential_id");



CREATE INDEX "webauthn_credentials_user_id_idx" ON "auth"."webauthn_credentials" USING "btree" ("user_id");



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



CREATE UNIQUE INDEX "bname" ON "storage"."buckets" USING "btree" ("name");



CREATE UNIQUE INDEX "bucketid_objname" ON "storage"."objects" USING "btree" ("bucket_id", "name");



CREATE UNIQUE INDEX "buckets_analytics_unique_name_idx" ON "storage"."buckets_analytics" USING "btree" ("name") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_multipart_uploads_list" ON "storage"."s3_multipart_uploads" USING "btree" ("bucket_id", "key", "created_at");



CREATE INDEX "idx_objects_bucket_id_name" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C");



CREATE INDEX "idx_objects_bucket_id_name_lower" ON "storage"."objects" USING "btree" ("bucket_id", "lower"("name") COLLATE "C");



CREATE INDEX "name_prefix_search" ON "storage"."objects" USING "btree" ("name" "text_pattern_ops");



CREATE UNIQUE INDEX "vector_indexes_name_bucket_id_idx" ON "storage"."vector_indexes" USING "btree" ("name", "bucket_id");



CREATE OR REPLACE TRIGGER "trg_sync_retailer_pending_debt" BEFORE INSERT OR UPDATE OF "total_assigned", "total_collected", "insta_pay_total_assigned", "insta_pay_total_collected" ON "public"."retailers" FOR EACH ROW EXECUTE FUNCTION "public"."sync_retailer_pending_debt"();



CREATE OR REPLACE TRIGGER "enforce_bucket_name_length_trigger" BEFORE INSERT OR UPDATE OF "name" ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."enforce_bucket_name_length"();



CREATE OR REPLACE TRIGGER "protect_buckets_delete" BEFORE DELETE ON "storage"."buckets" FOR EACH STATEMENT EXECUTE FUNCTION "storage"."protect_delete"();



CREATE OR REPLACE TRIGGER "protect_objects_delete" BEFORE DELETE ON "storage"."objects" FOR EACH STATEMENT EXECUTE FUNCTION "storage"."protect_delete"();



CREATE OR REPLACE TRIGGER "update_objects_updated_at" BEFORE UPDATE ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."update_updated_at_column"();



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "mfa_amr_claims_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_challenges"
    ADD CONSTRAINT "mfa_challenges_auth_factor_id_fkey" FOREIGN KEY ("factor_id") REFERENCES "auth"."mfa_factors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."one_time_tokens"
    ADD CONSTRAINT "one_time_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_flow_state_id_fkey" FOREIGN KEY ("flow_state_id") REFERENCES "auth"."flow_state"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_oauth_client_id_fkey" FOREIGN KEY ("oauth_client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sso_domains"
    ADD CONSTRAINT "sso_domains_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."webauthn_challenges"
    ADD CONSTRAINT "webauthn_challenges_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."webauthn_credentials"
    ADD CONSTRAINT "webauthn_credentials_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "fk_users_retailer" FOREIGN KEY ("retailer_id") REFERENCES "public"."retailers"("id");



ALTER TABLE ONLY "public"."investor_profit_snapshots"
    ADD CONSTRAINT "investor_profit_snapshots_investor_id_fkey" FOREIGN KEY ("investor_id") REFERENCES "public"."investors"("id");



ALTER TABLE ONLY "public"."partner_profit_snapshots"
    ADD CONSTRAINT "partner_profit_snapshots_partner_id_fkey" FOREIGN KEY ("partner_id") REFERENCES "public"."partners"("id");



ALTER TABLE ONLY "public"."rollback_snapshots"
    ADD CONSTRAINT "rollback_snapshots_point_id_fkey" FOREIGN KEY ("point_id") REFERENCES "public"."rollback_points"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_upload_id_fkey" FOREIGN KEY ("upload_id") REFERENCES "storage"."s3_multipart_uploads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."vector_indexes"
    ADD CONSTRAINT "vector_indexes_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets_vectors"("id");



ALTER TABLE "auth"."audit_log_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."flow_state" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."identities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."instances" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_amr_claims" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_challenges" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_factors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."one_time_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."refresh_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."saml_providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."saml_relay_states" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."schema_migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sso_domains" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sso_providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."users" ENABLE ROW LEVEL SECURITY;


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



ALTER TABLE "storage"."buckets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_analytics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_vectors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."objects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads_parts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."vector_indexes" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "auth" TO "anon";
GRANT USAGE ON SCHEMA "auth" TO "authenticated";
GRANT USAGE ON SCHEMA "auth" TO "service_role";
GRANT ALL ON SCHEMA "auth" TO "supabase_auth_admin";
GRANT ALL ON SCHEMA "auth" TO "dashboard_user";
GRANT USAGE ON SCHEMA "auth" TO "postgres";



GRANT USAGE ON SCHEMA "extensions" TO "anon";
GRANT USAGE ON SCHEMA "extensions" TO "authenticated";
GRANT USAGE ON SCHEMA "extensions" TO "service_role";
GRANT ALL ON SCHEMA "extensions" TO "dashboard_user";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT USAGE ON SCHEMA "storage" TO "postgres" WITH GRANT OPTION;
GRANT USAGE ON SCHEMA "storage" TO "anon";
GRANT USAGE ON SCHEMA "storage" TO "authenticated";
GRANT USAGE ON SCHEMA "storage" TO "service_role";
GRANT ALL ON SCHEMA "storage" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON SCHEMA "storage" TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."email"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."jwt"() TO "postgres";
GRANT ALL ON FUNCTION "auth"."jwt"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."role"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."uid"() TO "dashboard_user";



REVOKE ALL ON FUNCTION "extensions"."grant_pg_cron_access"() FROM "supabase_admin";
GRANT ALL ON FUNCTION "extensions"."grant_pg_cron_access"() TO "supabase_admin" WITH GRANT OPTION;
GRANT ALL ON FUNCTION "extensions"."grant_pg_cron_access"() TO "dashboard_user";



GRANT ALL ON FUNCTION "extensions"."grant_pg_graphql_access"() TO "postgres" WITH GRANT OPTION;



REVOKE ALL ON FUNCTION "extensions"."grant_pg_net_access"() FROM "supabase_admin";
GRANT ALL ON FUNCTION "extensions"."grant_pg_net_access"() TO "supabase_admin" WITH GRANT OPTION;
GRANT ALL ON FUNCTION "extensions"."grant_pg_net_access"() TO "dashboard_user";



GRANT ALL ON FUNCTION "extensions"."pgrst_ddl_watch"() TO "postgres" WITH GRANT OPTION;



GRANT ALL ON FUNCTION "extensions"."pgrst_drop_watch"() TO "postgres" WITH GRANT OPTION;



GRANT ALL ON FUNCTION "extensions"."set_graphql_placeholder"() TO "postgres" WITH GRANT OPTION;



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



GRANT ALL ON TABLE "auth"."audit_log_entries" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."audit_log_entries" TO "postgres";
GRANT SELECT ON TABLE "auth"."audit_log_entries" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "auth"."custom_oauth_providers" TO "postgres";
GRANT ALL ON TABLE "auth"."custom_oauth_providers" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."flow_state" TO "postgres";
GRANT SELECT ON TABLE "auth"."flow_state" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."flow_state" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."identities" TO "postgres";
GRANT SELECT ON TABLE "auth"."identities" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."identities" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."instances" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."instances" TO "postgres";
GRANT SELECT ON TABLE "auth"."instances" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_amr_claims" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_amr_claims" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_amr_claims" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_challenges" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_challenges" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_challenges" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_factors" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_factors" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_factors" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_authorizations" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_authorizations" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_client_states" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_client_states" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_clients" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_clients" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_consents" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_consents" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."one_time_tokens" TO "postgres";
GRANT SELECT ON TABLE "auth"."one_time_tokens" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."one_time_tokens" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."refresh_tokens" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."refresh_tokens" TO "postgres";
GRANT SELECT ON TABLE "auth"."refresh_tokens" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON SEQUENCE "auth"."refresh_tokens_id_seq" TO "dashboard_user";
GRANT ALL ON SEQUENCE "auth"."refresh_tokens_id_seq" TO "postgres";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."saml_providers" TO "postgres";
GRANT SELECT ON TABLE "auth"."saml_providers" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."saml_providers" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."saml_relay_states" TO "postgres";
GRANT SELECT ON TABLE "auth"."saml_relay_states" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."saml_relay_states" TO "dashboard_user";



GRANT SELECT ON TABLE "auth"."schema_migrations" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sessions" TO "postgres";
GRANT SELECT ON TABLE "auth"."sessions" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sessions" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sso_domains" TO "postgres";
GRANT SELECT ON TABLE "auth"."sso_domains" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sso_domains" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sso_providers" TO "postgres";
GRANT SELECT ON TABLE "auth"."sso_providers" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sso_providers" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."users" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."users" TO "postgres";
GRANT SELECT ON TABLE "auth"."users" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "auth"."webauthn_challenges" TO "postgres";
GRANT ALL ON TABLE "auth"."webauthn_challenges" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."webauthn_credentials" TO "postgres";
GRANT ALL ON TABLE "auth"."webauthn_credentials" TO "dashboard_user";



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



REVOKE ALL ON TABLE "storage"."buckets" FROM "supabase_storage_admin";
GRANT ALL ON TABLE "storage"."buckets" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON TABLE "storage"."buckets" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets" TO "anon";
GRANT ALL ON TABLE "storage"."buckets" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."buckets_analytics" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "anon";



GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "service_role";
GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "authenticated";
GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "anon";



REVOKE ALL ON TABLE "storage"."objects" FROM "supabase_storage_admin";
GRANT ALL ON TABLE "storage"."objects" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON TABLE "storage"."objects" TO "service_role";
GRANT ALL ON TABLE "storage"."objects" TO "authenticated";
GRANT ALL ON TABLE "storage"."objects" TO "anon";
GRANT ALL ON TABLE "storage"."objects" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."s3_multipart_uploads" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "anon";



GRANT ALL ON TABLE "storage"."s3_multipart_uploads_parts" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "anon";



GRANT SELECT ON TABLE "storage"."vector_indexes" TO "service_role";
GRANT SELECT ON TABLE "storage"."vector_indexes" TO "authenticated";
GRANT SELECT ON TABLE "storage"."vector_indexes" TO "anon";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON SEQUENCES TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON FUNCTIONS TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON TABLES TO "dashboard_user";












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






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "service_role";




