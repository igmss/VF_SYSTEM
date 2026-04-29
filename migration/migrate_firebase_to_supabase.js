const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseServiceKey) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Auto-detect latest Firebase export file
const projectRoot = path.join(__dirname, '..');
const allFiles = fs.readdirSync(projectRoot).filter(f => f.startsWith('vodatracking-default-rtdb-export') && f.endsWith('.json')).sort();
const latestExport = allFiles[allFiles.length - 1];
if (!latestExport) { console.error('No Firebase export file found in project root.'); process.exit(1); }
const EXPORT_FILE = path.join(projectRoot, latestExport);

function toSnakeCase(str) {
  if (str === 'isActive') return 'is_active';
  return str.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`)
    .replace(/([a-z])([0-9])/g, '$1_$2');
}

function parseToBigint(val) {
  if (!val) return null;
  if (typeof val === 'number') return val;
  const timestamp = Date.parse(val);
  if (!isNaN(timestamp)) return timestamp;
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
    }
  }

  const { count, error: countError } = await supabase
    .from(tableName)
    .select('*', { count: 'exact', head: true });

  if (!countError) {
    console.log(`✅ ${tableName} now has ${count} rows.`);
  }
}

async function clearFinancialData() {
  console.log('\n⚠️  Clearing stale financial data before fresh migration...');

  const tablesToClear = [
    'financial_ledger',
    'transactions',
    'loans',
    'investors',
    'partners',
    'retailer_assignment_requests',
    'daily_stats',
    'daily_flow_summary',
    'system_profit_snapshots',
    'investor_profit_snapshots',
    'partner_profit_snapshots',
    'retailers',
    'collectors',
    'bank_accounts',
    'mobile_numbers',
    'users',
    'system_config'
  ];

  for (const table of tablesToClear) {
    try {
      let { error } = await supabase.from(table).delete().neq('id', '00000000-0000-0000-0000-000000000000');
      if (error) {
        error = (await supabase.from(table).delete().neq('key', '___non_existent___')).error;
      }
      if (error) {
        error = (await supabase.from(table).delete().neq('date_key', '___non_existent___')).error;
      }
      
      if (error) console.log(`  Could not clear ${table}: ${error.message}`);
      else console.log(`  Cleared ${table} ✓`);
    } catch (e) {
      console.log(`  Could not clear ${table}: ${e.message}`);
    }
  }

  console.log('Financial tables cleared. Starting fresh migration...\n');
}

async function run() {
  console.log('===========================================');
  console.log(' Firebase to Supabase Migration');
  console.log(' Using:', latestExport);
  console.log('===========================================\n');

  if (!fs.existsSync(EXPORT_FILE)) {
    console.error(`Export file not found: ${EXPORT_FILE}`);
    console.error('Please ensure the Firebase export file is in the project root folder.');
    process.exit(1);
  }

  const rawData = fs.readFileSync(EXPORT_FILE, 'utf8');
  const data = JSON.parse(rawData);

  console.log(`Loaded Firebase export, found keys: ${Object.keys(data).join(', ')}\n`);

  await clearFinancialData();

  // 1. Fetch real Auth IDs from Supabase to prevent profile loss and fix linking
  const { data: authUsers, error: authError } = await supabase.auth.admin.listUsers();
  const authIdMap = {}; // email -> Supabase ID
  if (!authError && authUsers?.users) {
    authUsers.users.forEach(u => {
      if (u.email) authIdMap[u.email.toLowerCase()] = u.id;
    });
  }

  // 2. Build UID Map (Firebase UID -> Supabase ID)
  const firebaseToSupabaseUidMap = {};
  if (data.users) {
    Object.entries(data.users).forEach(([fbUid, user]) => {
      const email = user.email?.toLowerCase();
      if (email && authIdMap[email]) {
        firebaseToSupabaseUidMap[fbUid] = authIdMap[email];
      } else {
        firebaseToSupabaseUidMap[fbUid] = fbUid; // Fallback
      }
    });
  }

  // 3. Migrate Users
  await migrateTable('users', data.users, (id, item) => {
    const email = item.email?.toLowerCase();
    const supId = authIdMap[email] || item.firebaseUid || id;
    return {
      firebase_uid: supId,
      email: item.email,
      name: item.name,
      role: item.role,
      is_active: item.isActive ?? true,
      retailer_id: item.retailerId,
      created_at: item.createdAt
    };
  }, 'email');

  // 4. Migrate Collectors (using remapped IDs)
  await migrateTable('collectors', data.collectors, (id, item) => {
    const supId = firebaseToSupabaseUidMap[id];
    const row = transformObject(item);
    return {
      ...row,
      id: supId || id,
      uid: supId || row.uid || id
    };
  });

  // 5. Migrate Retailers (using remapped assigned_collector_id)
  await migrateTable('retailers', data.retailers, (id, item) => {
    const row = transformObject(item);
    if (row.assigned_collector_id && firebaseToSupabaseUidMap[row.assigned_collector_id]) {
      row.assigned_collector_id = firebaseToSupabaseUidMap[row.assigned_collector_id];
    }
    return row;
  });

  await migrateTable('bank_accounts', data.bank_accounts, (id, item) => transformObject(item));

  await migrateTable('mobile_numbers', data.mobile_numbers, (id, item) => {
    const row = transformObject(item);
    // Remove any unknown columns not in Supabase schema
    delete row.name;
    return row;
  });

  await migrateTable('investors', data.investors, (id, item) => {
    const row = transformObject(item);
    if (row.created_by_uid && firebaseToSupabaseUidMap[row.created_by_uid]) {
      row.created_by_uid = firebaseToSupabaseUidMap[row.created_by_uid];
    }
    return {
      ...row,
      investment_date: parseToBigint(item.investmentDate),
      created_at: parseToBigint(item.createdAt),
      last_paid_at: parseToBigint(item.lastPaidAt),
      capital_history: typeof item.capitalHistory === 'object' ? item.capitalHistory : {}
    };
  });

  await migrateTable('loans', data.loans, (id, item) => {
    const row = transformObject(item);
    if (row.created_by_uid && firebaseToSupabaseUidMap[row.created_by_uid]) {
      row.created_by_uid = firebaseToSupabaseUidMap[row.created_by_uid];
    }
    if (row.source_id && firebaseToSupabaseUidMap[row.source_id]) {
      row.source_id = firebaseToSupabaseUidMap[row.source_id];
    }
    return {
      ...row,
      issued_at: parseToBigint(item.issuedAt),
      repaid_at: parseToBigint(item.repaidAt),
      last_updated_at: parseToBigint(item.lastUpdatedAt)
    };
  });

  await migrateTable('transactions', data.transactions, (id, item) => transformObject(item), 'bybit_order_id');

  await migrateTable('financial_ledger', data.financial_ledger, (id, item) => {
    const row = transformObject(item);
    if (row.from_id && firebaseToSupabaseUidMap[row.from_id]) {
      row.from_id = firebaseToSupabaseUidMap[row.from_id];
    }
    if (row.to_id && firebaseToSupabaseUidMap[row.to_id]) {
      row.to_id = firebaseToSupabaseUidMap[row.to_id];
    }
    if (row.created_by_uid && firebaseToSupabaseUidMap[row.created_by_uid]) {
      row.created_by_uid = firebaseToSupabaseUidMap[row.created_by_uid];
    }
    return row;
  });

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

  const syncState = {
    id: 1,
    last_synced_order_ts: data.sync_data?.lastSyncedOrderTs || data.app_state?.last_synced_order_ts || 0,
    last_sync_time: data.app_state?.lastSyncTime,
    last_server_sync_status: data.app_state?.lastServerSyncStatus
  };
  await supabase.from('sync_state').upsert(syncState);
  console.log('✅ Migrated sync_state');

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

  if (data.system_config?.partners) {
    await migrateTable('partners', data.system_config.partners, (id, item) => transformObject(item));
  }

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
  console.log(' Migration completed successfully!');
  console.log('===========================================');

  // ── Post-migration verification ─────────────────────────────────────────
  console.log('\n📊 Verifying migrated data in Supabase...');
  const { data: sims } = await supabase.from('mobile_numbers').select('phone_number, in_total_used, out_total_used, initial_balance');
  if (sims) {
    console.log('\nVF Number Balances (from Supabase):');
    sims.forEach(n => {
      const balance = (n.initial_balance || 0) + (n.in_total_used || 0) - (n.out_total_used || 0);
      console.log(`  ${n.phone_number}: Balance = ${balance.toFixed(2)} EGP (in=${n.in_total_used}, out=${n.out_total_used})`);
    });
  }

  // Compare key values against export
  const { data: syncRow } = await supabase.from('sync_state').select('last_synced_order_ts').eq('id', 1).single();
  console.log('\nSync State last_synced_order_ts:', syncRow?.last_synced_order_ts);
  console.log('\n✅ Verification complete. If balances look correct, the migration succeeded.');
  console.log('⚠️  Next: Run the profit snapshot rebuild function to recalculate');
  console.log('    investor and partner profit snapshots with the corrected logic.');
}

run().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});
