const fs = require('fs');

const jsonPath = 'd:/New folder/vodafone_system/vodatracking-default-rtdb-export.json';
const db = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));

function asNumber(val) {
    if (!val) return 0;
    const n = parseFloat(val);
    return isNaN(n) ? 0 : n;
}

// 1. VF Profit per 1000 (USDT Spread)
const ledger = db.financial_ledger || {};
let sumBuy = 0, countBuy = 0;
let sumSell = 0, countSell = 0;

Object.values(ledger).forEach(tx => {
    const price = asNumber(tx.usdtPrice);
    if (tx.type === 'BUY_USDT' && price > 0) {
        sumBuy += price;
        countBuy++;
    } else if (tx.type === 'SELL_USDT' && price > 0) {
        sumSell += price;
        countSell++;
    }
});

const lastExchangePrice = asNumber(db.usd_exchange?.lastPrice || 0);

// Fallback logic matching adminFinance.js
const avgBuy = countBuy > 0 ? (sumBuy / countBuy) : lastExchangePrice;
const avgSell = countSell > 0 ? (sumSell / countSell) : (avgBuy * 1.015);

let vfProfitPer1000 = 0;
if (avgBuy > 0 && avgSell > avgBuy) {
    // Formula: ( (1000 / BuyPrice) * SellPrice - 1000 ) - 1 EGP Fee
    vfProfitPer1000 = ((1000 / avgBuy) * avgSell - 1000) - 1;
}

// 2. InstaPay Profit per 1000 (Weighted Retailer Average)
let totalInstaPayVolume = 0;
let totalInstaPayProfitVolume = 0;

const retailers = db.retailers || {};
Object.values(retailers).forEach(r => {
    const vol = asNumber(r.instaPayTotalCollected);
    const rate = asNumber(r.instaPayProfitPer1000);
    const profit = (vol / 1000) * rate;
    
    totalInstaPayVolume += vol;
    totalInstaPayProfitVolume += profit;
});

const instaProfitPer1000 = totalInstaPayVolume > 0 
    ? (totalInstaPayProfitVolume / totalInstaPayVolume) * 1000 
    : 0;

console.log('--- Profit Rate Extraction Report ---');
console.log('');
console.log('1. [VF] Vodafone Cash (USDT-Based)');
console.log(`- Average Buy Price: ${avgBuy.toFixed(2)} EGP`);
console.log(`- Average Sell Price: ${avgSell.toFixed(2)} EGP`);
console.log(`- Price Spread: ${(avgSell - avgBuy).toFixed(2)} EGP (${((avgSell / avgBuy - 1) * 100).toFixed(2)}%)`);
console.log(`> VF PROFIT PER 1000: ${vfProfitPer1000.toFixed(2)} EGP`);
console.log('');
console.log('2. [INSTA] InstaPay (Retailer-Based)');
console.log(`- Total InstaPay Volume: ${totalInstaPayVolume.toLocaleString()} EGP`);
console.log(`- Total InstaPay Profit Pool: ${totalInstaPayProfitVolume.toLocaleString()} EGP`);
console.log(`> INSTA PROFIT PER 1000: ${instaProfitPer1000.toFixed(2)} EGP`);
console.log('');
console.log('---');
