-- Safe script to enable Realtime for all core tables
-- Run this in the Supabase SQL Editor

DO $$
DECLARE
    tbl text;
    tables_to_add text[] := ARRAY[
        'financial_ledger', 
        'retailers', 
        'collectors', 
        'bank_accounts', 
        'loans', 
        'investors', 
        'partners', 
        'usd_exchange', 
        'system_profit_snapshots', 
        'retailer_assignment_requests', 
        'transactions', 
        'sync_state', 
        'system_config'
    ];
BEGIN
    -- 1. Create publication if it doesn't exist (Supabase default is usually supabase_realtime)
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;

    -- 2. Add each table if not already present in the publication
    FOREACH tbl IN ARRAY tables_to_add
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables 
            WHERE pubname = 'supabase_realtime' AND tablename = tbl
        ) THEN
            BEGIN
                EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I', tbl);
                RAISE NOTICE 'Added table % to supabase_realtime publication', tbl;
            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE 'Could not add table %: %', tbl, SQLERRM;
            END;
        ELSE
            RAISE NOTICE 'Table % is already in supabase_realtime publication', tbl;
        END IF;
    END LOOP;
END $$;
