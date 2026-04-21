const fs = require('fs');
const path = require('path');

// Mock data
const dbData = JSON.parse(fs.readFileSync('d:/New folder/vodafone_system/vodatracking-default-rtdb-export (77).json', 'utf8'));

// Helper mocks (extracted from actual helpers.js if necessary, or just use real ones)
const helpers = require('../functions/src/shared/helpers');
const profitEngine = require('../functions/src/shared/profitEngine');

// Mock the dbData structure expected by profitEngine functions
const mockDbData = {
    openingCapital: dbData.system_config?.opening_capital || 175000,
    investorsSnap: { 
        exists: () => !!dbData.investors, 
        forEach: (cb) => Object.entries(dbData.investors || {}).forEach(([id, val]) => cb({ val: () => ({ ...val, id }), key: id })),
        val: () => dbData.investors
    },
    loansSnap: { 
        exists: () => !!dbData.loans, 
        forEach: (cb) => Object.entries(dbData.loans || {}).forEach(([id, val]) => cb({ val: () => val, key: id })),
        val: () => dbData.loans
    },
    banksSnap: { 
        exists: () => !!dbData.bank_accounts, 
        forEach: (cb) => Object.entries(dbData.bank_accounts || {}).forEach(([id, val]) => cb({ val: () => val, key: id })),
        val: () => dbData.bank_accounts
    },
    mobileNumbersSnap: { 
        exists: () => !!dbData.vf_numbers, 
        forEach: (cb) => Object.entries(dbData.vf_numbers || {}).forEach(([id, val]) => cb({ val: () => val, key: id })),
        val: () => dbData.vf_numbers
    },
    retailersSnap: { 
        exists: () => !!dbData.retailers, 
        forEach: (cb) => Object.entries(dbData.retailers || {}).forEach(([id, val]) => cb({ val: () => val, key: id })),
        val: () => dbData.retailers
    },
    collectorsSnap: { 
        exists: () => !!dbData.collectors, 
        forEach: (cb) => Object.entries(dbData.collectors || {}).forEach(([id, val]) => cb({ val: () => val, key: id })),
        val: () => dbData.collectors
    },
    usdSnap: { 
        exists: () => !!dbData.system?.usd_exchange, 
        val: () => dbData.system?.usd_exchange
    },
    ledgerSnap: { 
        exists: () => !!dbData.financial_ledger, 
        forEach: (cb) => Object.entries(dbData.financial_ledger || {}).forEach(([id, val]) => cb({ val: () => val, key: id })),
        val: () => dbData.financial_ledger
    }
};

const dateStr = '2026-04-14';
const performance = profitEngine._getPerformanceForDateRange(mockDbData, dateStr, 1);
const reconciliation = profitEngine._computeReconciledProfit(mockDbData);
const systemSnapshot = profitEngine._buildSystemProfitSnapshotForDate(mockDbData, dateStr);

console.log('--- RECONCILIATION ---');
console.log(reconciliation);

console.log('--- PERFORMANCE (APR 14) ---');
console.log(performance);

console.log('--- SYSTEM SNAPSHOT (APR 14) ---');
console.log(systemSnapshot);

// Investor Simulation
const investor = Object.values(dbData.investors || {})[0]; // Take first one
if (investor) {
    const invSnap = profitEngine._buildInvestorSnapshotForDate(investor, systemSnapshot);
    console.log('--- INVESTOR SNAPSHOT (APR 14) ---');
    console.log(invSnap);
}

// Partner Simulation
const partner = Object.values(dbData.partners || {})[0]; // Take first one
if (partner) {
    const totalInvestorProfitDeducted = 250; // Mock deduction
    const partSnap = profitEngine._buildPartnerSnapshotForDate(partner, systemSnapshot, totalInvestorProfitDeducted);
    console.log('--- PARTNER SNAPSHOT (APR 14) ---');
    console.log(partSnap);
}
