-- Enable necessary extensions
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 1. Reset Daily Limits (runs daily at 22:01 GMT / 00:01 Cairo)
select cron.schedule(
  'reset-daily-limits-job',
  '1 22 * * *',
  $$
  select net.http_post(
    url := 'https://slddrodjourpwjcxrnoa.supabase.co/functions/v1/reset-daily-limits',
    headers := '{"Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNsZGRyb2Rqb3VycHdqY3hybm9hIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NzAzNDczNywiZXhwIjoyMDkyNjEwNzM3fQ.-fOqlJ3Jh0iTUjG5qPmNA5Fz_qF5BHysaFY9aUEHU08", "Content-Type": "application/json"}'::jsonb
  );
  $$
);

-- 2. Sync Bybit Orders (runs every 1 minute)
select cron.schedule(
  'sync-bybit-orders-job',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://slddrodjourpwjcxrnoa.supabase.co/functions/v1/sync-bybit-orders',
    headers := '{"Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNsZGRyb2Rqb3VycHdqY3hybm9hIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NzAzNDczNywiZXhwIjoyMDkyNjEwNzM3fQ.-fOqlJ3Jh0iTUjG5qPmNA5Fz_qF5BHysaFY9aUEHU08", "Content-Type": "application/json"}'::jsonb
  );
  $$
);
