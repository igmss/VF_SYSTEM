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

const EXPORT_FILE = path.join(__dirname, '../vodatracking-default-rtdb-export - 2026-04-24T224716.596.json');

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
    // Handle cases like "2026-04-10"
    const parts = val.split('-');
    if (parts.length === 3) {
      return new Date(val).getTime();
    }
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
  if (!data) {
    console.log(`No data for ${tableName}, skipping.`);
    return;
  }

  let rows = Object.entries(data).map(([id, item]) => {
    const row = transformFn(id, item);
    // Remove undefined/null values to allow DB defaults to kick in
    Object.keys(row).forEach(key => {
      if (row[key] === undefined || row[key] === null) {
        delete row[key];
      }
    });
    return row;
  });

  // Deduplicate rows based on onConflict key to avoid "ON CONFLICT DO UPDATE command cannot affect row a second time"
  if (onConflict && onConflict !== 'id') {
    const seen = new Set();
    rows = rows.filter(row => {
      if (!row[onConflict]) return true; // Keep rows without the conflict key (though they might fail later)
      if (seen.has(row[onConflict])) return false;
      seen.add(row[onConflict]);
      return true;
    });
  }
  
  console.log(`Upserting ${rows.length} rows into ${tableName}...`);
  
  // Batch upsert to avoid payload limits
  const BATCH_SIZE = 500;
  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const batch = rows.slice(i, i + BATCH_SIZE);
    const { error } = await supabase
      .from(tableName)
      .upsert(batch, { onConflict: onConflict });
    
    if (error) {
      console.error(`Error upserting into ${tableName}:`, error);
      throw error;
    }
  }
  
  const { count, error: countError } = await supabase
    .from(tableName)
    .select('*', { count: 'exact', head: true });
  
  if (countError) {
    console.error(`Error counting ${tableName}:`, countError);
  } else {
    console.log(`Success: ${tableName} now has ${count} rows.`);
  }
}

async function run() {
  console.log('Starting migration...');
  
  if (!fs.existsSync(EXPORT_FILE)) {
    console.error(`Export file not found: ${EXPORT_FILE}`);
    process.exit(1);
  }

  const rawData = fs.readFileSync(EXPORT_FILE, 'utf8');
  const data = JSON.parse(rawData);

  // 1. Retailers
  await migrateTable('retailers', data.retailers, (id, item) => transformObject(item));

  // 2. Users
  await migrateTable('users', data.users, (id, item) => ({
    id: item.id || undefined, // Use existing UUID if present
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
    id: id, // Firebase UID is the key
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

  // 8. Transactions
  await migrateTable('transactions', data.transactions, (id, item) => transformObject(item), 'bybit_order_id');

  // 9. Financial Ledger
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
    console.log('Migrated usd_exchange');
  }

  // 11. Sync State (Merge app_state and sync_data)
  const syncState = {
    id: 1,
    last_synced_order_ts: data.sync_data?.lastSyncedOrderTs || 0,
    last_sync_time: data.app_state?.lastSyncTime,
    last_server_sync_status: data.app_state?.lastServerSyncStatus
  };
  await supabase.from('sync_state').upsert(syncState);
  console.log('Migrated sync_state');

  // 12. System Config (Key-Value)
  const systemEntries = [];
  if (data.system) {
    for (const [key, value] of Object.entries(data.system)) {
      systemEntries.push({ key, value });
    }
  }
  if (data.system_config) {
    for (const [key, value] of Object.entries(data.system_config)) {
      if (key !== 'partners') { // Partners goes to its own table
        systemEntries.push({ key, value });
      }
    }
  }
  if (systemEntries.length > 0) {
    await supabase.from('system_config').upsert(systemEntries);
    console.log(`Migrated ${systemEntries.length} system_config entries`);
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
    await supabase.from('daily_flow_summary').upsert(flowData);
    console.log(`Migrated ${flowData.length} daily_flow_summary entries`);
  }

  // 15. Daily Stats (Flattening)
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
      console.log(`Upserting ${dailyStatsRows.length} daily_stats rows...`);
      for (let i = 0; i < dailyStatsRows.length; i += 500) {
        await supabase.from('daily_stats').upsert(dailyStatsRows.slice(i, i + 500));
      }
      console.log('Migrated daily_stats');
    }
  }

  console.log('Migration completed successfully!');
}

if (require.main === module) {
  run().catch(err => {
    console.error('Migration failed:', err);
    process.exit(1);
  });
}

module.exports = { run };
