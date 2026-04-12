const fs = require('fs');

/**
 * FINAL PRE-IMPLEMENTATION LOGIC TEST
 * This script simulates the exact output of the upcoming Code Changes
 */

const jsonPath = 'd:/New folder/vodafone_system/vodatracking-default-rtdb-export (34).json';
const db = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));

// --- Ground Truth Constants ---
const USER_BANK = 77690;
const USER_WALLETS = 57152;
const USER_DEBT = 93382;
const USER_CASH = 62802;
const USER_USD_EGP = 0.01;

const OPENING_CAPITAL = 180000;
const INVESTOR_CAPITAL = 100000;
const LOAN_OUTSTANDING = 5000;

function asNumber(val) {
    if (!val) return 0;
    const n = parseFloat(val);
    return isNaN(n) ? 0 : n;
}

// --- 1. Accurate Asset Calculation ---
const currentTotalAssets = USER_BANK + USER_WALLETS + USER_DEBT + USER_CASH + USER_USD_EGP;
const totalInitialWealth = OPENING_CAPITAL + INVESTOR_CAPITAL;

// --- 2. Accurate Surplus & Daily Flow ---
// Revenue - (Asset Gaps) - Liabilities
const totalVfCollected = Object.values(db.retailers || {}).reduce((acc, r) => acc + asNumber(r.totalCollected), 0);
const operatingDays = 24; // March 18 to April 11

const rawVfSurplus = totalVfCollected - (currentTotalAssets - totalInitialWealth) - LOAN_OUTSTANDING;
const dailyVfFlow = Math.max(0, rawVfSurplus) / operatingDays;

// InstaPay Flow (Last 2 days volume)
let instaVol = 0;
Object.values(db.financial_ledger).forEach(tx => {
    if (tx.type === 'DISTRIBUTE_INSTAPAY') instaVol += asNumber(tx.amount);
});
const dailyInstaFlow = instaVol / 2;

// --- 3. Gross Profit & Expenses ---
const vfProfitRate = 16.95; // From USDT analysis
const instaProfitRate = 5.00; // From Retailer analysis

const grossVfProfit = (dailyVfFlow / 1000) * vfProfitRate;
const grossInstaProfit = (dailyInstaFlow / 1000) * instaProfitRate;

let totalDailyExpenses = 0;
Object.values(db.financial_ledger).forEach(tx => {
    if (tx.type.includes('EXPENSE') || tx.type.includes('FEE')) {
        totalDailyExpenses += asNumber(tx.amount);
    }
});
// Average daily expense
const avgDailyExpense = totalDailyExpenses / operatingDays;

const businessNetProfit = (grossVfProfit + grossInstaProfit) - avgDailyExpense;

// --- 4. Investor Profit (Hurdle: 90k) ---
const hurdle = OPENING_CAPITAL / 2; // 90,000 EGP
const combinedFlow = dailyVfFlow + dailyInstaFlow;

let genaProfit = 0;
if (combinedFlow > hurdle) {
    // Only share profit on the excess volume above hurdle
    const excess = combinedFlow - hurdle;
    // Basis: max of (half your investment)
    const investorBasis = Math.min(excess, 100000 / 2);
    // Yield: Basis * Profit Rate * 40% Share
    genaProfit = (investorBasis / 1000) * vfProfitRate * 0.40;
}

// --- 5. Partner Split ---
const partnerPool = businessNetProfit - genaProfit;

console.log('--- FINAL SYSTEM SIMULATION REPORT ---');
console.log(`Date: 2026-04-11 | Start: 2026-03-18 (${operatingDays} days)`);
console.log('');
console.log('[1] ASSET STATE (The Accuracy Fix)');
console.log(`- Bank Balance: ${USER_BANK.toLocaleString()} EGP`);
console.log(`- VF Wallets: ${USER_WALLETS.toLocaleString()} EGP (NEW)`);
console.log(`- Total Liquid Assets: ${currentTotalAssets.toLocaleString()} EGP`);
console.log('');
console.log('[2] DAILY FLOWS (The Engine)');
console.log(`- VF Daily Flow: ${dailyVfFlow.toLocaleString()} EGP/day`);
console.log(`- Insta Daily Flow: ${dailyInstaFlow.toLocaleString()} EGP/day`);
console.log(`- Combined Flow: ${combinedFlow.toLocaleString()} EGP/day`);
console.log(`- Investor Hurdle: ${hurdle.toLocaleString()} EGP/day`);
console.log('');
console.log('[3] PROFIT & LOSS (The Net Model)');
console.log(`- Gross VF Profit: ${grossVfProfit.toFixed(2)} EGP/day`);
console.log(`- Gross Insta Profit: ${grossInstaProfit.toFixed(2)} EGP/day`);
console.log(`- Total Expenses/Fees (Daily Avg): ${avgDailyExpense.toFixed(2)} EGP/day`);
console.log(`> BUSINESS NET PROFIT: ${businessNetProfit.toFixed(2)} EGP/day`);
console.log('');
console.log('[4] FINAL DISTRIBUTIONS');
console.log(`- Investor (Gena) Profit: ${genaProfit.toFixed(2)} EGP/day (Status: ${combinedFlow > hurdle ? 'PAID' : 'BELOW HURDLE'})`);
console.log(`- Partner Pool: ${partnerPool.toFixed(2)} EGP/day`);
console.log('  - Mostafa Abbas (40%): ' + (partnerPool * 0.40).toFixed(2));
console.log('  - Ibrahim (35%): ' + (partnerPool * 0.35).toFixed(2));
console.log('  - Mostafa Galhom (25%): ' + (partnerPool * 0.25).toFixed(2));
console.log('');
console.log('--- TEST COMPLETE ---');
console.log('Next Step: Implement this logic into functions/src/adminFinance.js');
