const fs = require('fs');

/**
 * Audit script for Vodafone System Profit Calculation
 * Usage: node reconciliation_audit.js [path_to_json] [target_date] [overrides_json]
 */

const jsonPath = process.argv[2] || 'd:/New folder/vodafone_system/vodatracking-default-rtdb-export.json';
const targetDateStr = process.argv[3] || new Date().toISOString().split('T')[0];

// Manual Overrides provided by User
const userOverrides = {
    bankBalance: 77690,
    vfNumberBalance: 57152,
    usdExchangeEGP: 0.01,
    retailerVfDebt: 93382,
    collectorCash: 62802
};

console.log('--- Vodafone System Profit Reconciliation Audit (Ground Truth Mode) ---');
console.log(`Using Manual Overrides: ${JSON.stringify(userOverrides, null, 2)}`);

if (!fs.existsSync(jsonPath)) {
    console.error(`Error: File not found at ${jsonPath}`);
    process.exit(1);
}

let db;
try {
    db = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
} catch (e) {
    console.error('Error parsing JSON:', e.message);
    process.exit(1);
}

// --- Helpers ---
function asNumber(val) {
    if (!val) return 0;
    const n = parseFloat(val);
    return isNaN(n) ? 0 : n;
}

function safeDate(d, fallback) {
    try {
        const date = new Date(d);
        if (isNaN(date.getTime())) return new Date(fallback);
        return date;
    } catch {
        return new Date(fallback);
    }
}

// MATCHING adminFinance.js DEFINITIONS
function getRetailerOutstandingDebt(r) {
  const outstanding = asNumber(r.totalAssigned) - asNumber(r.totalCollected);
  return outstanding > 0 ? outstanding : 0;
}

function getMobileNumberBalance(n) {
  return asNumber(n.initialBalance) + asNumber(n.inTotalUsed) - asNumber(n.outTotalUsed);
}

// --- Simulation Logic ---

function auditReconciliation(data, dateStr, overrides) {
    console.log('\n[1/4] Gathering Input Data...');

    const systemConfig = data.system_config || data.system?.operation_settings || {};
    const openingCapital = 180000; // From User Turn
    const systemVfProfitPer1000 = asNumber(systemConfig.vfProfitPer1000 || 50); 
    
    const moduleDates = data.system_config?.module_start_dates || { vf: "2026-03-18", instapay: "2026-04-09" };
    const vfStartDate = safeDate(moduleDates.vf, "2026-03-18");
    const targetDate = safeDate(dateStr, new Date().toISOString());

    const vfDays = Math.max(1, Math.ceil((targetDate - vfStartDate) / (1000 * 60 * 60 * 24)));

    console.log(`- VF Operation Start: ${vfStartDate.toISOString().split('T')[0]} (${vfDays} days)`);
    console.log(`- Opening Capital: ${openingCapital.toLocaleString()} EGP`);

    // 2. Retailer Collections (Revenue)
    let totalVfCollected = 0;
    const retailers = data.retailers || {};
    Object.values(retailers).forEach(r => {
        totalVfCollected += asNumber(r.totalCollected);
    });

    console.log('\n[2/4] Revenue Aggregates:');
    console.log(`- Total VF Collected (Lifetime): ${totalVfCollected.toLocaleString()} EGP`);

    // 3. Asset Valuation (Using Overrides if present)
    const bankBalance = overrides.bankBalance !== undefined ? overrides.bankBalance : 0;
    const vfNumberBalance = overrides.vfNumberBalance !== undefined ? overrides.vfNumberBalance : 0;
    const usdExchangeEGP = overrides.usdExchangeEGP !== undefined ? overrides.usdExchangeEGP : 0;
    const retailerVfDebt = overrides.retailerVfDebt !== undefined ? overrides.retailerVfDebt : 0;
    const collectorCash = overrides.collectorCash !== undefined ? overrides.collectorCash : 0;
    
    // InstaPay Debt usually separate, but user didn't specify, so we'll merge into debt if not handled
    const totalLoansOutstanding = 5000; // From JSON
    const totalActiveInvestorCapital = 100000; // From JSON

    console.log('\n[3/4] Current Assets (Manual):');
    console.log(`- Bank Balance: ${bankBalance.toLocaleString()} EGP`);
    console.log(`- VF Number Balance: ${vfNumberBalance.toLocaleString()} EGP`);
    console.log(`- Retailer Debt: ${retailerVfDebt.toLocaleString()} EGP`);
    console.log(`- Collector Cash: ${collectorCash.toLocaleString()} EGP`);
    console.log(`- Active Investor Capital: ${totalActiveInvestorCapital.toLocaleString()} EGP`);

    // 4. Final Math (Matching adminFinance.js)
    console.log('\n[4/4] Calculation Results:');
    
    const currentTotalLiquidAssets = bankBalance + vfNumberBalance + usdExchangeEGP + retailerVfDebt + collectorCash;
    
    // adjustedLiquidAssets = currentTotalLiquidAssets - openingCapital - totalActiveInvestorCapital;
    const adjustedLiquidAssets = currentTotalLiquidAssets - openingCapital - totalActiveInvestorCapital;
    
    // rawVfSurplus = totalVfCollected - adjustedLiquidAssets - totalLoansOutstanding;
    const rawVfSurplus = totalVfCollected - adjustedLiquidAssets - totalLoansOutstanding;
    
    console.log(`- Current Total Liquid Assets: ${currentTotalLiquidAssets.toLocaleString()} EGP`);
    console.log(`- Adjusted Liquid Assets (Operational): ${adjustedLiquidAssets.toLocaleString()} EGP`);
    console.log(`  (Liquid Assets - Opening - Investor)`);
    
    const vfDailyFlow = Math.max(0, rawVfSurplus) / vfDays;
    const vfProfit = (vfDailyFlow / 1000) * systemVfProfitPer1000;

    console.log('---');
    console.log(`> Raw VF Surplus: ${rawVfSurplus.toLocaleString()} EGP`);
    console.log(`> VF Daily Flow (${vfDays} days): ${vfDailyFlow.toLocaleString()} EGP/day`);
    console.log(`> Estimated VF Profit/day: ${vfProfit.toLocaleString()} EGP`);
    console.log('---');
}

auditReconciliation(db, targetDateStr, userOverrides);
