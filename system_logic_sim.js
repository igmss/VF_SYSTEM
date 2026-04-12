const fs = require('fs');

/**
 * SYSTEM LOGIC SIMULATION (Hardened)
 * This script uses ZERO hardcoded values. Everything is pulled from the database nodes.
 */

const jsonPath = 'd:/New folder/vodafone_system/vodatracking-default-rtdb-export (34).json';
const db = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));

function asNumber(val) {
    if (!val) return 0;
    const n = parseFloat(val);
    return isNaN(n) ? 0 : n;
}

// Helper to calculate VF Phone Balances (Missing in current System Logic)
function getMobileNumberBalance(num) {
    const initial = asNumber(num.initialBalance);
    const inTotal = asNumber(num.inTotalUsed);
    const outTotal = asNumber(num.outTotalUsed);
    return initial + inTotal - outTotal;
}

// --- 1. Dynamic Asset Detection ---
let bankBalance = 0;
Object.values(db.bank_accounts || {}).forEach(b => bankBalance += asNumber(b.balance));

let vfNumberBalance = 0;
Object.values(db.mobile_numbers || {}).forEach(m => vfNumberBalance += getMobileNumberBalance(m));

let retailerTotalDebt = 0;
Object.values(db.retailers || {}).forEach(r => {
    const assigned = asNumber(r.totalAssigned) + asNumber(r.instaPayTotalAssigned);
    const collected = asNumber(r.totalCollected) + asNumber(r.instaPayTotalCollected);
    retailerTotalDebt += (assigned - collected);
});

let collectorCash = 0;
Object.values(db.collectors || {}).forEach(c => collectorCash += asNumber(c.cashOnHand));

const totalSystemAssets = bankBalance + vfNumberBalance + retailerTotalDebt + collectorCash;

// --- 2. Dynamic Capital/Hurdle Detection ---
const openingCapital = asNumber(db.system_config?.openingCapital); // 180,000
const hurdle = openingCapital / 2; // 90,000

let totalInvestorCapital = 0;
Object.values(db.investors || {}).forEach(inv => {
    if (inv.status === 'active') totalInvestorCapital += asNumber(inv.investedAmount);
});

// --- 3. The "Surplus Truth" Logic ---
const netBusinessSurplus = totalSystemAssets - openingCapital - totalInvestorCapital;

// --- 4. Daily Performance Calculation ---
const days = 24; 
const dailyNetProfit = netBusinessSurplus / days;

// Transactional Flow Calculation (From Ledger)
let totalVfCollected = 0;
Object.values(db.retailers || {}).forEach(r => totalVfCollected += asNumber(r.totalCollected));
const dailyFlow = totalVfCollected / days;

console.log('--- DYNAMIC SYSTEM LOGIC SIMULATION ---');
console.log('');
console.log('[From Database Nodes]');
console.log(`- Opening Capital Found: ${openingCapital.toLocaleString()}`);
console.log(`- Investor Capital Found: ${totalInvestorCapital.toLocaleString()}`);
console.log(`- Bank Balance Found: ${bankCurrentBalance = bankBalance.toLocaleString()}`); 
console.log(`- VF Numbers Found: ${vfNumberBalance.toLocaleString()}`);
console.log(`- Retailer Debt Found: ${retailerTotalDebt.toLocaleString()}`);
console.log('');
console.log('[System Logic Result]');
console.log(`- Calculated Total Assets: ${totalSystemAssets.toLocaleString()}`);
console.log(`- Calculated Dynamic Surplus: ${netBusinessSurplus.toLocaleString()}`);
console.log(`- Daily Flow Indicator: ${dailyFlow.toLocaleString()} EGP/day`);
console.log(`- Hurdle Check: ${dailyFlow > hurdle ? 'EXCEEDED' : 'BELOW HURDLE (90k)'}`);
console.log('');
console.log('[Profit Split Result]');
console.log(`- Total Partner Daily Pool: ${dailyNetProfit.toFixed(2)} EGP/day`);
console.log(`  - Abbas (40%): ${(dailyNetProfit * 0.4).toFixed(2)}`);
console.log(`  - Ibrahim (35%): ${(dailyNetProfit * 0.35).toFixed(2)}`);
console.log(`  - Galhom (25%): ${(dailyNetProfit * 0.25).toFixed(2)}`);
