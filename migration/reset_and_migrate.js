const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseServiceKey) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey);

async function resetDatabase() {
  console.log('Resetting database...');
  const sql = `
    SET session_replication_role = 'replica';
    TRUNCATE TABLE 
        financial_ledger,
        transactions,
        loans,
        investors,
        partners,
        collectors,
        users,
        retailers,
        mobile_numbers,
        bank_accounts,
        daily_flow_summary,
        daily_stats,
        system_profit_snapshots,
        investor_profit_snapshots,
        partner_profit_snapshots,
        sync_state,
        system_config,
        usd_exchange
    CASCADE;
    SET session_replication_role = 'origin';
  `;
  
  // We use a custom RPC to run raw SQL if available, or just use the migrate_to_supabase logic
  // Since we don't have a 'run_sql' RPC usually, we'll try to delete everything via client
  const tables = [
    'financial_ledger', 'transactions', 'loans', 'investors', 'partners',
    'collectors', 'users', 'retailers', 'mobile_numbers', 'bank_accounts',
    'daily_flow_summary', 'daily_stats', 'system_profit_snapshots',
    'investor_profit_snapshots', 'partner_profit_snapshots', 'sync_state',
    'system_config', 'usd_exchange'
  ];

  for (const table of tables) {
    console.log(`Clearing ${table}...`);
    const { error } = await supabase.from(table).delete().neq('id', '00000000-0000-0000-0000-000000000000');
    if (error) {
      console.warn(`Warning clearing ${table}:`, error.message);
    }
  }
}

async function run() {
  await resetDatabase();
  console.log('Database cleared. Starting migration...');
  
  const migrateScript = require('./migrate_to_supabase.js');
  await migrateScript.run();
}

run().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});
