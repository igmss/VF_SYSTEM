const fs = require('fs');
const engine = require('./functions/src/shared/profitEngine.js');
const helpers = require('./functions/src/shared/helpers.js');

const data = JSON.parse(fs.readFileSync('d:\\\\New folder\\\\vodafone_system\\\\vodatracking-default-rtdb-export (82).json', 'utf8'));

function mockSnap(obj) {
  return {
    exists: () => obj != null && Object.keys(obj).length > 0,
    val: () => obj,
    forEach: (cb) => {
      if (!obj) return false;
      for (const [key, value] of Object.entries(obj)) {
        cb({ key, val: () => value });
      }
    }
  };
}

const dbData = {
  openingCapital: data.system_config?.openingCapital || 0,
  ledgerSnap: mockSnap(data.financial_ledger),
  banksSnap: mockSnap(data.bank_accounts),
  usdSnap: mockSnap(data.usd_exchange),
  retailersSnap: mockSnap(data.retailers),
  collectorsSnap: mockSnap(data.collectors),
  loansSnap: mockSnap(Object.fromEntries(Object.entries(data.loans || {}).filter(([k, v]) => v.status === 'active'))),
  moduleDatesSnap: mockSnap(data.system_config?.module_start_dates),
  investorsSnap: mockSnap(Object.fromEntries(Object.entries(data.investors || {}).filter(([k, v]) => v.status === 'active'))),
  mobileNumbersSnap: mockSnap(data.mobile_numbers)
};

const dates = new Set();
if (data.financial_ledger) {
  for (const t of Object.values(data.financial_ledger)) {
    if (t.timestamp) {
       dates.add(new Date(t.timestamp).toISOString().split('T')[0]);
    }
  }
}

const sortedDates = Array.from(dates).sort();
// Just log the last 3 dates to see recent results without overwhelming stdout
const recentDates = sortedDates.slice(-3);

let output = '';

const activeInvestors = [];
if (dbData.investorsSnap.exists()) {
  dbData.investorsSnap.forEach(child => {
    activeInvestors.push({ ...child.val(), id: child.key });
  });
}
activeInvestors.sort((a, b) => engine.formatDateKey(a.investmentDate).localeCompare(engine.formatDateKey(b.investmentDate)));

const activePartners = [];
if (data.system_config?.partners) {
  for (const [k, v] of Object.entries(data.system_config.partners)) {
    if (v.status !== 'inactive') activePartners.push({...v, id: k});
  }
}

for (const dayKey of recentDates) {
  const systemSnapshot = engine._buildSystemProfitSnapshotForDate(dbData, dayKey);
  
  output += `\n=== Date: ${dayKey} ===\n`;
  output += `Total Flow: ${systemSnapshot.totalFlow.toFixed(2)}\n`;
  output += `Net Profit: ${systemSnapshot.totalNetProfit.toFixed(2)}\n\n`;

  let precedingCapital = 0;
  let totalInvestorProfit = 0;
  
  output += `--- Investors ---\n`;
  for (const investor of activeInvestors) {
    if (!engine.isInvestorEligibleForDate(investor, dayKey)) {
      precedingCapital += helpers.asNumber(investor.investedAmount);
      continue;
    }
    
    const invSnap = engine._buildInvestorSnapshotForDate(
        investor,
        systemSnapshot,
        precedingCapital,
        dbData.openingCapital,
        null
    );
    totalInvestorProfit += helpers.asNumber(invSnap.investorProfit);
    precedingCapital += helpers.asNumber(investor.investedAmount);
    
    output += `Investor: ${investor.name || investor.id}
  Hurdle: ${invSnap.hurdle.toFixed(2)}
  Excess: ${invSnap.excess.toFixed(2)}
  Calculated Profit: ${invSnap.investorProfit.toFixed(2)}\n`;
  }

  output += `\n--- Partners ---\n`;
  for (const partner of activePartners) {
    const partSnap = engine._buildPartnerSnapshotForDate(
      partner,
      systemSnapshot,
      totalInvestorProfit,
      null
    );
    output += `Partner: ${partner.name || partner.id}
  Calculated Profit: ${partSnap.partnerProfit.toFixed(2)}\n`;
  }
}

console.log(output);
