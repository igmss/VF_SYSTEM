const fs = require('fs');

/**
 * FINAL VERIFICATION V2 (Net Profit & Investor Hurdle)
 * This script uses the user's defined "16,027 EGP" lifetime profit
 * and applies the 90k Hurdle / Half-Base logic.
 */

const jsonPath = 'd:/New folder/vodafone_system/vodatracking-default-rtdb-export (34).json';
const db = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));

// --- Ground Truth Data ---
const TOTAL_ASSETS = 291027;
const TOTAL_CAPITAL = 275000;
const LIFETIME_PROFIT = TOTAL_ASSETS - TOTAL_CAPITAL; // 16,027

const OPENING_BUSINESS_CAPITAL = 175000;
const INVESTOR_CAPITAL = 100000;
const DAYS = 24;

// --- 1. Daily Performance ---
const dailyNetProfit = LIFETIME_PROFIT / DAYS;

// --- 2. Flow Extraction for Hurdle ---
// We need to know the Transactional Flow to see if we cross the 90k Hurdle.
const totalVfCollected = Object.values(db.retailers || {}).reduce((acc, r) => acc + (parseFloat(r.totalCollected) || 0), 0);
const dailyVfFlow = totalVfCollected / DAYS; 

// Combined flow (VF + Insta)
// Based on ledger, Insta is approx 24k/day
const dailyInstaFlow = 24000; 
const combinedDailyFlow = dailyVfFlow + dailyInstaFlow;

// --- 3. Investor Hurdle Logic ---
const hurdle = 180000 / 2; // 90,000 EGP as per user request
const investorProfitShare = 0.40; // 40%

let genaProfit = 0;
let status = "BELOW HURDLE";

if (combinedDailyFlow > hurdle) {
    status = "ABOVE HURDLE";
    const excess = combinedDailyFlow - hurdle;
    // Rule: Profit on half of invested amount only
    const investorBasis = Math.min(excess, INVESTOR_CAPITAL / 2);
    // Approximate profit rate per 1000
    const profitRate = 16.95; 
    genaProfit = (investorBasis / 1000) * profitRate * investorProfitShare;
}

// --- 4. Partner Split ---
const partnerPool = dailyNetProfit - genaProfit;

console.log('--- FINAL VERIFICATION V2 REPORT ---');
console.log(`- Lifetime Business Profit: ${LIFETIME_PROFIT.toLocaleString()} EGP`);
console.log(`- Daily Business Net Profit: ${dailyNetProfit.toFixed(2)} EGP/day`);
console.log('');
console.log(`[Hurdle Check]`);
console.log(`- Combined Daily Flow: ${combinedDailyFlow.toLocaleString()} EGP/day`);
console.log(`- Hurdle (50% Opening): ${hurdle.toLocaleString()} EGP/day`);
console.log(`- Investor Profit: ${genaProfit.toFixed(2)} EGP/day (${status})`);
console.log('');
console.log(`[Partner Distributions]`);
console.log(`- Total Partner Daily Pool: ${partnerPool.toFixed(2)} EGP/day`);
console.log(`  - Mostafa Abbas (40%): ${(partnerPool * 0.4).toFixed(2)}`);
console.log(`  - Ibrahim (35%): ${(partnerPool * 0.35).toFixed(2)}`);
console.log(`  - Mostafa Galhom (25%): ${(partnerPool * 0.25).toFixed(2)}`);
console.log('');
console.log('--- END OF REPORT ---');
