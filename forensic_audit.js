const fs = require('fs');

const jsonPath = 'd:/New folder/vodafone_system/vodatracking-default-rtdb-export (34).json';
const db = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));

// Ground Truth (User Provided)
const REAL_ASSETS = 291026.01;
const LOANS = 5000;
const CAPITAL = 280000; // 180k Opening + 100k Investor

function asNumber(val) {
    if (!val) return 0;
    const n = parseFloat(val);
    return isNaN(n) ? 0 : n;
}

/**
 * We are tracking the "EGP Cash Pool"
 * Inflows increase EGP. Outflows decrease EGP.
 */
let cashIn = 0;
let cashOut = 0;

const detail = {};

Object.values(db.financial_ledger).forEach(tx => {
    const type = tx.type;
    const amount = asNumber(tx.amount);
    
    if (!detail[type]) detail[type] = 0;
    detail[type] += amount;

    switch(type) {
        case 'INVESTOR_CAPITAL_IN':
        case 'INVESTOR_CAPITAL_ADD':
        case 'COLLECT_CASH':       // Money taken from retailers
        case 'COLLECT_INSTAPAY_CASH':
        case 'SELL_USDT':          // Sold USDT for EGP (Cash In)
        case 'CREDIT_RETURN':      // Retailer returned credit for EGP? (Actually usually credit out, cash in)
            cashIn += amount;
            break;
        
        case 'BUY_USDT':           // Paid EGP to buy USDT (Cash Out)
        case 'DEPOSIT_TO_VFCASH':  // Buying credit (Cash Out)
        case 'DISTRIBUTE_VFCASH':  // Giving credit to retailer (Cash Out)
        case 'LOAN_ISSUED':
        case 'EXPENSE_VFCASH_FEE':
        case 'INTERNAL_VF_TRANSFER_FEE':
        case 'EXPENSE_INSTAPAY_FEE':
        case 'CREDIT_RETURN_FEE':
        case 'DISTRIBUTE_INSTAPAY':
            cashOut += amount;
            break;
            
        default:
            // Other types might be internal (FUND_BANK, DEPOSIT_TO_BANK) 
            // which don't change the TOTAL pool, just the location.
            break;
    }
});

// The 180k Opening Capital is not in the ledger, so we add it as an inflow.
const calculatedCash = (180000) + cashIn - cashOut;

console.log('--- FORENSIC EGP CASH FLOW AUDIT ---');
console.log('');
console.log(`- Calculated Cash (Start + ΣIn - ΣOut): ${calculatedCash.toLocaleString()} EGP`);
console.log(`- Actual Assets (Bank + VF + Debt + Coll): ${REAL_ASSETS.toLocaleString()} EGP`);
console.log('');
console.log(`- DISCREPANCY: ${(calculatedCash - REAL_ASSETS).toFixed(2)} EGP`);
console.log('');
console.log('--- Flow Details ---');
console.log(`- Cash Inflows: ${cashIn.toLocaleString()} EGP`);
console.log(`- Cash Outflows: ${cashOut.toLocaleString()} EGP`);
console.log('');
console.log('--- Breakdown of Inputs ---');
console.log(JSON.stringify(detail, null, 2));
