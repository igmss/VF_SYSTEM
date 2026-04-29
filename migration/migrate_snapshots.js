const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

const EXPORT_FILE = path.join(__dirname, '../vodatracking-default-rtdb-export - 2026-04-25T142438.398.json');

// Fields that exist in Firebase but NOT in the Supabase schema
const SKIP_FIELDS = new Set(['date', 'id']);

// Explicit overrides for camelCase fields that don't convert cleanly via regex
const FIELD_RENAMES = {
  isActive: 'is_active',
  isPaid: 'is_paid',
  instaNetPer1000: 'insta_net_per_1000',
  vfNetPer1000: 'vf_net_per_1000',
  feeRatePer1000: 'fee_rate_per_1000',
  profitPer1000: 'profit_per_1000',
  instaInvestorProfit: 'insta_investor_profit',
  vfInvestorProfit: 'vf_investor_profit',
  instaExcess: 'insta_excess',
  vfExcess: 'vf_excess',
  instaFlow: 'insta_flow',
  vfFlow: 'vf_flow',
  totalFlow: 'total_flow',
  instaGrossProfit: 'insta_gross_profit',
  instaFeeCost: 'insta_fee_cost',
  vfSpreadProfit: 'vf_spread_profit',
  vfDepositProfit: 'vf_deposit_profit',
  vfDiscountCost: 'vf_discount_cost',
  vfFeeCost: 'vf_fee_cost',
  instaNetProfit: 'insta_net_profit',
  vfNetProfit: 'vf_net_profit',
  globalAvgBuyPrice: 'global_avg_buy_price',
  dailyAvgBuyPrice: 'daily_avg_buy_price',
  usdExchangeEgp: 'usd_exchange_egp',
  usdExchangeEGP: 'usd_exchange_egp',
  usdExchangeEgP: 'usd_exchange_egp',
  openingCapital: 'opening_capital',
  effectiveStartingCapital: 'effective_starting_capital',
  totalOutstandingLoans: 'total_outstanding_loans',
  currentTotalAssets: 'current_total_assets',
  bankBalance: 'bank_balance',
  vfNumberBalance: 'vf_number_balance',
  retailerDebt: 'retailer_debt',
  retailerInstaDebt: 'retailer_insta_debt',
  collectorCash: 'collector_cash',
  usdExchangeEgp: 'usd_exchange_egp',
  adjustedTotalAssets: 'adjusted_total_assets',
  reconciledProfit: 'reconciled_profit',
  workingDays: 'working_days',
  calculationVersion: 'calculation_version',
  calculatedAt: 'calculated_at',
  sellEntriesCount: 'sell_entries_count',
  buyEntriesRangeCount: 'buy_entries_range_count',
  totalNetProfit: 'total_net_profit',
  totalVfDistributed: 'total_vf_distributed',
  totalInstaDistributed: 'total_insta_distributed',
  totalSellUsdt: 'total_sell_usdt',
  totalSellEgp: 'total_sell_egp',
  totalEarned: 'total_earned',
  totalPaid: 'total_paid',
  paidAt: 'paid_at',
  paidByUid: 'paid_by_uid',
  paidFromType: 'paid_from_type',
  paidFromId: 'paid_from_id',
  profitSharePercent: 'profit_share_percent',
  precedingCapital: 'preceding_capital',
  totalLoansOutstanding: 'total_loans_outstanding',
  currentBankBalance: 'current_bank_balance',
  retailerVfDebt: 'retailer_vf_debt',
  allocationRatio: 'allocation_ratio',
  reconciledPool: 'reconciled_pool',
  totalInvestorProfitDeducted: 'total_investor_profit_deducted',
  remainingForPartners: 'remaining_for_partners',
  partnerProfit: 'partner_profit',
  sharePercent: 'share_percent',
  vfDailyFlow: 'vf_daily_flow',
  instaDailyFlow: 'insta_daily_flow',
  totalDailyFlow: 'total_daily_flow',
  investorProfit: 'investor_profit',
  investorId: 'investor_id',
  partnerId: 'partner_id',
};

function toField(key) {
  if (SKIP_FIELDS.has(key)) return null;
  if (FIELD_RENAMES[key]) return FIELD_RENAMES[key];
  // Fallback: generic camelCase → snake_case
  return key
    .replace(/[A-Z]/g, l => `_${l.toLowerCase()}`)
    .replace(/([a-z])([0-9])/g, '$1_$2');
}

function transformSnapshotRow(obj) {
  const result = {};
  for (const [key, value] of Object.entries(obj)) {
    const targetKey = toField(key);
    if (targetKey === null) continue;
    result[targetKey] = value;
  }
  return result;
}

async function upsertBatch(tableName, rows, conflictKey) {
  if (rows.length === 0) return;
  const BATCH = 100;
  for (let i = 0; i < rows.length; i += BATCH) {
    const { error } = await supabase
      .from(tableName)
      .upsert(rows.slice(i, i + BATCH), { onConflict: conflictKey });
    if (error) {
      console.error(`  Batch error in ${tableName}:`, error.message);
    }
  }
}

async function migrateSystemProfitSnapshots(data) {
  const snaps = data.system_profit_snapshots;
  if (!snaps || typeof snaps !== 'object') {
    console.log('No system_profit_snapshots found, skipping.');
    return;
  }
  const rows = [];
  for (const [key, value] of Object.entries(snaps)) {
    if (typeof value !== 'object' || !value) continue;
    const isDateKey = /^\d{4}-\d{2}-\d{2}$/.test(key);
    if (isDateKey) {
      rows.push({ date_key: key, ...transformSnapshotRow(value) });
    } else {
      // Nested structure: key is something else, values may be date-keyed
      for (const [dateKey, snap] of Object.entries(value)) {
        if (/^\d{4}-\d{2}-\d{2}$/.test(dateKey) && typeof snap === 'object' && snap) {
          rows.push({ date_key: dateKey, ...transformSnapshotRow(snap) });
        }
      }
    }
  }
  if (rows.length === 0) {
    console.log('system_profit_snapshots: no valid rows found (stored as full DB dumps).');
    return;
  }
  console.log(`Upserting ${rows.length} system_profit_snapshots rows...`);
  await upsertBatch('system_profit_snapshots', rows, 'date_key');
  const { count } = await supabase.from('system_profit_snapshots').select('*', { count: 'exact', head: true });
  console.log(`✅ system_profit_snapshots now has ${count} rows.`);
}

async function migrateInvestorProfitSnapshots(data) {
  const snaps = data.investor_profit_snapshots;
  if (!snaps || typeof snaps !== 'object') {
    console.log('No investor_profit_snapshots found, skipping.');
    return;
  }
  const rows = [];
  for (const [investorId, dateMap] of Object.entries(snaps)) {
    if (typeof dateMap !== 'object' || !dateMap) continue;
    for (const [dateKey, snap] of Object.entries(dateMap)) {
      if (typeof snap !== 'object' || !snap) continue;
      rows.push({ investor_id: investorId, date_key: dateKey, ...transformSnapshotRow(snap) });
    }
  }
  if (rows.length === 0) {
    console.log('investor_profit_snapshots: no valid rows found.');
    return;
  }
  console.log(`Upserting ${rows.length} investor_profit_snapshots rows...`);
  await upsertBatch('investor_profit_snapshots', rows, 'investor_id,date_key');
  const { count } = await supabase.from('investor_profit_snapshots').select('*', { count: 'exact', head: true });
  console.log(`✅ investor_profit_snapshots now has ${count} rows.`);
}

async function migratePartnerProfitSnapshots(data) {
  const snaps = data.partner_profit_snapshots;
  if (!snaps || typeof snaps !== 'object') {
    console.log('No partner_profit_snapshots found, skipping.');
    return;
  }
  const rows = [];
  for (const [partnerId, dateMap] of Object.entries(snaps)) {
    if (typeof dateMap !== 'object' || !dateMap) continue;
    for (const [dateKey, snap] of Object.entries(dateMap)) {
      if (typeof snap !== 'object' || !snap) continue;
      rows.push({ partner_id: partnerId, date_key: dateKey, ...transformSnapshotRow(snap) });
    }
  }
  if (rows.length === 0) {
    console.log('partner_profit_snapshots: no valid rows found.');
    return;
  }
  console.log(`Upserting ${rows.length} partner_profit_snapshots rows...`);
  await upsertBatch('partner_profit_snapshots', rows, 'partner_id,date_key');
  const { count } = await supabase.from('partner_profit_snapshots').select('*', { count: 'exact', head: true });
  console.log(`✅ partner_profit_snapshots now has ${count} rows.`);
}

async function run() {
  console.log('=========================================');
  console.log(' Migrating Profit Snapshots from Firebase');
  console.log('=========================================\n');
  if (!fs.existsSync(EXPORT_FILE)) {
    console.error('Export file not found:', EXPORT_FILE);
    process.exit(1);
  }
  console.log('Parsing JSON...');
  const data = JSON.parse(fs.readFileSync(EXPORT_FILE, 'utf8'));
  console.log('JSON parsed.\n');
  await migrateSystemProfitSnapshots(data);
  await migrateInvestorProfitSnapshots(data);
  await migratePartnerProfitSnapshots(data);
  console.log('\n=========================================');
  console.log(' Snapshot migration complete!');
  console.log('=========================================');
}

run().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});
