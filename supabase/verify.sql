-- Step 6: Verify the Schema

-- 1. Table count check — confirm all 15 tables exist
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- 2. Index check
SELECT indexname, tablename FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- 3. RLS check
SELECT tablename, rowsecurity FROM pg_tables
WHERE schemaname = 'public';

-- 4. Extensions check
SELECT extname FROM pg_extension WHERE extname IN ('uuid-ossp','pg_cron');
