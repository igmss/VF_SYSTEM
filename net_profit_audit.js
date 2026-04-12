const fs = require('fs');

/**
 * Net-Profit Reconciliation Audit
 * This script validates that:
 * Real Assets - Capital = (Total Trade Profit - Total Expenses)
 */

const jsonPath = 'd:/New folder/vodafone_system/vodatracking-default-rtdb-export (34).json';
const db = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));

// --- User Ground Truth (Current State) ---
const BANK_BALANCE = 77690;
const VF_WALLETS = 57152;
const RETAILER_DEBT = 93382;
const COLLECTOR_CASH = 62802;
const USD_BALANCE_EGP = 0.01; // From JSON (34)
const LOANS_OUTSTANDING = 5000;

const OPENING_CAPITAL = 180000;
const INVESTOR_CAPITAL = 100000;

function asNumber(val) {
    if (!val) return 0;
    const n = parseFloat(val);
    return isNaN(n) ? 0 : n;
}

// --- 1. Calculate Real-World Surplus ---
const currentTotalAssets = BANK_BALANCE + VF_WALLETS + RETAILER_DEBT + COLLECTOR_CASH + USD_BALANCE_EGP;
const totalInitialCapital = OPENING_CAPITAL + INVESTOR_CAPITAL;
const realNetSurplus = currentTotalAssets - totalInitialCapital - LOANS_OUTSTANDING;

// --- 2. Calculate Transactional Profit ---
let totalBuyEgp = 0;
let totalSellEgp = 0;
let totalInstaProfit = 0;

Object.values(db.financial_ledger).forEach(tx => {
    if (tx.type === 'BUY_USDT') totalBuyEgp += asNumber(tx.amount);
    if (tx.type === 'SELL_USDT') totalSellEgp += asNumber(tx.amount);
    if (tx.type === 'INSTAPAY_DIST_PROFIT') totalInstaProfit += asNumber(tx.amount);
});

const grossTradingProfit = (totalSellEgp - totalBuyEgp) + totalInstaProfit;

// --- 3. Calculate Operational Expenses (The "Leak") ---
let totalExpenses = 0;
const expenseLog = [];

Object.values(db.financial_ledger).forEach(tx => {
    if (tx.type.includes('EXPENSE') || tx.type.includes('FEE')) {
        const amt = asNumber(tx.amount);
        totalExpenses += amt;
        expenseLog.push({ type: tx.type, amount: amt, note: tx.notes });
    }
});

const netTransactionalProfit = grossTradingProfit - totalExpenses;

// --- 4. Report & Comparison ---
console.log('--- ENHANCED NET-PROFIT AUDIT REPORT ---');
console.log('');
console.log('[PART A] Actual System Assets (The "Real Cash")');
console.log(`- Total Liquid Assets: ${currentTotalAssets.toLocaleString()} EGP`);
console.log(`- Total Capital: ${totalInitialCapital.toLocaleString()} EGP`);
console.log(`- Loans: ${LOANS_OUTSTANDING.toLocaleString()} EGP`);
console.log(`> REAL-WORLD NET SURPLUS: ${realNetSurplus.toLocaleString()} EGP`);
console.log('');
console.log('[PART B] Transactional Ledger (The "Engine")');
console.log(`- Gross Trading Profit: ${grossTradingProfit.toLocaleString()} EGP`);
console.log(`- Total Expenses/Fees: ${totalExpenses.toLocaleString()} EGP`);
console.log(`> NET CALCULATED PROFIT: ${netTransactionalProfit.toLocaleString()} EGP`);
console.log('');
console.log('[PART C] The Reconciliation (The "Proof")');
const difference = realNetSurplus - netTransactionalProfit;
console.log(`- Difference: ${difference.toFixed(2)} EGP`);

if (Math.abs(difference) < 10) {
    console.log('✅ SUCCESS: The ledger perfectly explains the current bank balance!');
} else {
    console.log('❌ DISCREPANCY: There are still untracked movements.');
}

console.log('\n--- Expense Breakdown ---');
expenseLog.forEach(e => console.log(`- ${e.type}: ${e.amount} EGP`));
