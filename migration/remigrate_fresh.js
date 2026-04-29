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

// ──────────────────────────────────────────────────
// Use the LATEST export file
// ──────────────────────────────────────────────────
const EXPORT_FILE = path.join(__dirname, '../vodatracking-default-rtdb-export - 2026-04-25T142438.398.json');

function toSnakeCase(str) {
  if (str === 'isActive') return 'is_active';
  return str.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`)
            .replace(/([a-z])([0-9])/g, '$1_$2');
}

function parseToBigint(val) {
  if (!val) return null;
  if (typeof val === 'number') return val;
  if (typeof val === 'string') {
    const timestamp = Date.parse(val);
    if (!isNaN(timestamp)) return timestamp;
  }
  return null;
}

function transformObject(obj, mapping = {}) {
  const result = {};
  for (const [key, value] of Object.entries(obj)) {
    const targetKey = mapping[key] || toSnakeCase(key);
    result[targetKey] = value;
  }
  return result;
}

async function migrateTable(tableName, data, transformFn, onConflict = 'id') {
  if (!data || Object.keys(data).length === 0) {
    console.log(`No data for ${tableName}, skipping.`);
    return;
  }

  let rows = Object.entries(data).map(([id, item]) => {
    const row = transformFn(id, item);
    Object.keys(row).forEach(key => {
      if (row[key] === undefined || row[key] === null) {
        delete row[key];
      }
    });
    return row;
  });

  // Deduplicate by conflict key
  if (onConflict && onConflict !== 'id') {
    const seen = new Set();
    rows = rows.filter(row => {
      if (!row[onConflict]) return true;
      if (seen.has(row[onConflict])) return false;
      seen.add(row[onConflict]);
      return true;
    });
  }

  console.log(`Upserting ${rows.length} rows into ${tableName}...`);

  const BATCH_SIZE = 500;
  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const batch = rows.slice(i, i + BATCH_SIZE);
    const { error } = await supabase
      .from(tableName)
      .upsert(batch, { onConflict });

    if (error) {
      console.error(`Error upserting batch into ${tableName}:`, error.message || error);
      // Continue with next batch rather than crashing
    }
  }

  const { count, error: countError } = await supabase
    .from(tableName)
    .select('*', { count: 'exact', head: true });

  if (!countError) {
    console.log(`✅ ${tableName} now has ${count} rows.`);
  }
}

async function clearAndRemigrate() {
  console.log('\n⚠️  Clearing stale financial data before fresh migration...');
  
  // Clear only the financial/operational tables — preserve users and auth mapping
  const tablesToClear = [
    'financial_ledger',
    'transactions',
    'loans',
    'investors',
    'partners',
    'retailer_requests',
    'daily_stats',
    'daily_flow_summary',
    'system_profit_snapshots',
    'investor_profit_snapshots',
    'partner_profit_snapshots',
    'system_config',
  ];

  for (const table of tablesToClear) {
    const { error } = await supabase.from(table).delete().neq('id', '00000000-0000-0000-0000-000000000000');
    if (error) {
      // Tables with non-UUID PKs need different approach
      const { error: e2 } = await supabase.from(table).delete().gte('id', 0);
      if (e2) {
        // Try text PK tables
        const { error: e3 } = await supabase.from(table).delete().neq('id', 'NEVER_EXISTS');
        if (e3) console.log(`  Could not clear ${table}: ${e3.message}`);
        else console.log(`  Cleared ${table} ✓`);
      } else {
        console.log(`  Cleared ${table} ✓`);
      }
    } else {
      console.log(`  Cleared ${table} ✓`);
    }
  }

  // Update bank accounts and mobile numbers with fresh data (upsert is safe)
  console.log('Financial tables cleared. Starting fresh migration...\n');
}

async function run() {
  console.log('===========================================');
  console.log(' Fresh Migration from: 2026-04-25T142438');
  console.log('===========================================\n');

  if (!fs.existsSync(EXPORT_FILE)) {
    console.error(`Export file not found: ${EXPORT_FILE}`);
    process.exit(1);
  }

  const rawData = fs.readFileSync(EXPORT_FILE, 'utf8');
  const data = JSON.parse(rawData);

  // Step 0: Clear stale data
  await clearAndRemigrate();

  // 1. Retailers (upsert — safe)
  await migrateTable('retailers', data.retailers, (id, item) => transformObject(item));

  // 2. Users (upsert — preserve Supabase UUIDs from previous phase3 migration)
  await migrateTable('users', data.users, (id, item) => ({
    firebase_uid: item.firebaseUid || id,
    email: item.email,
    name: item.name,
    role: item.role,
    is_active: item.isActive ?? true,
    retailer_id: item.retailerId,
    created_at: item.createdAt
  }), 'firebase_uid');

  // 3. Bank Accounts
  await migrateTable('bank_accounts', data.bank_accounts, (id, item) => transformObject(item));

  // 4. Mobile Numbers
  await migrateTable('mobile_numbers', data.mobile_numbers, (id, item) => transformObject(item));

  // 5. Collectors
  await migrateTable('collectors', data.collectors, (id, item) => ({
    id,
    ...transformObject(item)
  }));

  // 6. Investors
  await migrateTable('investors', data.investors, (id, item) => ({
    ...transformObject(item),
    investment_date: parseToBigint(item.investmentDate),
    created_at: parseToBigint(item.createdAt),
    last_paid_at: parseToBigint(item.lastPaidAt),
    capital_history: typeof item.capitalHistory === 'object' ? item.capitalHistory : {}
  }));

  // 7. Loans
  await migrateTable('loans', data.loans, (id, item) => ({
    ...transformObject(item),
    issued_at: parseToBigint(item.issuedAt),
    repaid_at: parseToBigint(item.repaidAt),
    last_updated_at: parseToBigint(item.lastUpdatedAt)
  }));

  // 8. Transactions (Bybit P2P orders)
  await migrateTable('transactions', data.transactions, (id, item) => transformObject(item), 'bybit_order_id');

  // 9. Financial Ledger (all 1562+ entries)
  await migrateTable('financial_ledger', data.financial_ledger, (id, item) => transformObject(item));

  // 10. USD Exchange
  if (data.usd_exchange) {
    const item = data.usd_exchange;
    await supabase.from('usd_exchange').upsert({
      id: 1,
      usdt_balance: item.usdtBalance || 0,
      last_price: item.lastPrice,
      last_updated_at: item.lastUpdatedAt || new Date().toISOString()
    });
    console.log('✅ Migrated usd_exchange');
  }

  // 11. Sync State
  const syncState = {
    id: 1,
    last_synced_order_ts: data.sync_data?.lastSyncedOrderTs || data.app_state?.last_synced_order_ts || 0,
    last_sync_time: data.app_state?.lastSyncTime,
    last_server_sync_status: data.app_state?.lastServerSyncStatus
  };
  await supabase.from('sync_state').upsert(syncState);
  console.log('✅ Migrated sync_state');

  // 12. System Config
  const systemEntries = [];
  if (data.system) {
    for (const [key, value] of Object.entries(data.system)) {
      systemEntries.push({ key, value });
    }
  }
  if (data.system_config) {
    for (const [key, value] of Object.entries(data.system_config)) {
      if (key !== 'partners') {
        systemEntries.push({ key, value });
      }
    }
  }
  if (systemEntries.length > 0) {
    await supabase.from('system_config').upsert(systemEntries);
    console.log(`✅ Migrated ${systemEntries.length} system_config entries`);
  }

  // 13. Partners
  if (data.system_config?.partners) {
    await migrateTable('partners', data.system_config.partners, (id, item) => transformObject(item));
  }

  // 14. Daily Flow Summary
  if (data.summary?.daily_flow) {
    const flowData = Object.entries(data.summary.daily_flow).map(([dateKey, stats]) => ({
      date_key: dateKey,
      vf_amount: stats.vf || 0,
      insta_amount: stats.insta || 0
    }));
    if (flowData.length > 0) {
      await supabase.from('daily_flow_summary').upsert(flowData);
      console.log(`✅ Migrated ${flowData.length} daily_flow_summary entries`);
    }
  }

  // 15. Daily Stats
  if (data.daily_stats) {
    const dailyStatsRows = [];
    for (const [year, months] of Object.entries(data.daily_stats)) {
      for (const [month, days] of Object.entries(months)) {
        for (const [day, dayData] of Object.entries(days)) {
          if (dayData.collectors) {
            for (const [collectorId, stats] of Object.entries(dayData.collectors)) {
              dailyStatsRows.push({
                year: parseInt(year),
                month: parseInt(month),
                day: parseInt(day),
                collector_id: collectorId,
                ...transformObject(stats)
              });
            }
          }
        }
      }
    }
    if (dailyStatsRows.length > 0) {
      for (let i = 0; i < dailyStatsRows.length; i += 500) {
        await supabase.from('daily_stats').upsert(dailyStatsRows.slice(i, i + 500));
      }
      console.log(`✅ Migrated ${dailyStatsRows.length} daily_stats rows`);
    }
  }

  console.log('\n===========================================');
  console.log(' Migration completed successfully! ');
  console.log('===========================================');
}

run().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});
