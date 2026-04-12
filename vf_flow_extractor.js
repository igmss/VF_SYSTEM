const fs = require('fs');

const jsonPath = 'd:/New folder/vodafone_system/vodatracking-default-rtdb-export.json';
const db = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));

const ledger = db.financial_ledger || {};
const dailyFlow = {};

Object.values(ledger).forEach(tx => {
    // We filter for VF-related types
    // COLLECT_CASH: Money from retailer to collector
    // DEPOSIT_TO_VFCASH: Money from collector to system wallets
    // DISTRIBUTE_VFCASH: Money from system wallets to retailers (payout)
    
    if (['COLLECT_CASH', 'DEPOSIT_TO_VFCASH', 'DISTRIBUTE_VFCASH'].includes(tx.type)) {
        const date = new Date(tx.timestamp).toISOString().split('T')[0];
        if (!dailyFlow[date]) {
            dailyFlow[date] = { 
                collections: 0, 
                deposits: 0, 
                distributions: 0,
                net_flow: 0
            };
        }
        
        const amount = parseFloat(tx.amount || 0);
        if (tx.type === 'COLLECT_CASH') dailyFlow[date].collections += amount;
        if (tx.type === 'DEPOSIT_TO_VFCASH') dailyFlow[date].deposits += amount;
        if (tx.type === 'DISTRIBUTE_VFCASH') dailyFlow[date].distributions += amount;
        
        // Net flow is what moved into the system (collections)
        dailyFlow[date].net_flow = dailyFlow[date].collections;
    }
});

console.log('--- VF Daily Flow Extraction (Sorted by Date) ---');
console.log('Date'.padEnd(12) + ' | ' + 'Collections'.padStart(12) + ' | ' + 'Deposits'.padStart(12) + ' | ' + 'Distributions'.padStart(12));
console.log('-'.repeat(60));

Object.keys(dailyFlow).sort().forEach(date => {
    const day = dailyFlow[date];
    console.log(
        date.padEnd(12) + ' | ' + 
        day.collections.toLocaleString().padStart(12) + ' | ' + 
        day.deposits.toLocaleString().padStart(12) + ' | ' + 
        day.distributions.toLocaleString().padStart(12)
    );
});

// Calculate Average
const dates = Object.keys(dailyFlow);
const totalCollections = dates.reduce((sum, d) => sum + dailyFlow[d].collections, 0);
const avg = totalCollections / (dates.length || 1);

console.log('-'.repeat(60));
console.log(`Summary:`);
console.log(`Total Days: ${dates.length}`);
console.log(`Total Collections: ${totalCollections.toLocaleString()} EGP`);
console.log(`Average Daily Flow: ${avg.toLocaleString(undefined, {maximumFractionDigits: 2})} EGP/day`);
console.log('---');
