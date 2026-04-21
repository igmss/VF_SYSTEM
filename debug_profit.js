const admin = require('firebase-admin');
const { v4: uuidv4 } = require('uuid');

// Mock helpers
function asNumber(v) { return parseFloat(v) || 0; }
function formatDateKey(dateInput) { return new Date(dateInput).toISOString().split('T')[0]; }

async function debugProfit() {
  if (!admin.apps.length) {
    admin.initializeApp({
      databaseURL: "https://vodatracking-default-rtdb.firebaseio.com"
    });
  }
  const db = admin.database();

  console.log("--- FETCHING DATA ---");
  const [
    configSnap,
    partnersSnap,
    investorsSnap,
    banksSnap,
    usdSnap,
    retailersSnap,
    collectorsSnap,
    loansSnap,
    moduleDatesSnap,
    flowSnap,
    mobileNumbersSnap
  ] = await Promise.all([
    db.ref('system_config/openingCapital').once('value'),
    db.ref('system_config/partners').once('value'),
    db.ref('investors').orderByChild('status').equalTo('active').once('value'),
    db.ref('bank_accounts').once('value'),
    db.ref('usd_exchange').once('value'),
    db.ref('retailers').once('value'),
    db.ref('collectors').once('value'),
    db.ref('loans').orderByChild('status').equalTo('active').once('value'),
    db.ref('system_config/module_start_dates').once('value'),
    db.ref('summary/daily_flow').once('value'),
    db.ref('mobile_numbers').once('value')
  ]);

  const openingCapital = asNumber(configSnap.val());
  console.log("Opening Capital:", openingCapital);

  let totalActiveInvestorCapital = 0;
  investorsSnap.forEach(c => { totalActiveInvestorCapital += asNumber(c.val().investedAmount); });
  console.log("Total Investor Capital:", totalActiveInvestorCapital);

  let totalOutstandingLoans = 0;
  loansSnap.forEach(c => { 
    const ln = c.val();
    totalOutstandingLoans += Math.max(0, asNumber(ln.principalAmount) - asNumber(ln.amountRepaid));
  });
  console.log("Total Outstanding Loans:", totalOutstandingLoans);

  let bankBalance = 0;
  banksSnap.forEach(c => { bankBalance += asNumber(c.val().balance); });
  console.log("Bank Balance:", bankBalance);

  let vfNumberBalance = 0;
  mobileNumbersSnap.forEach(c => { 
    const n = c.val();
    vfNumberBalance += (asNumber(n.balance) + asNumber(n.currentBalance) + asNumber(n.totalIn) - asNumber(n.totalOut) - asNumber(n.outTotalUsed));
    // Note: This matches the complex getMobileNumberBalance in helpers.js
  });
  console.log("VF Number Balance (Est):", vfNumberBalance);

  let retailerDebt = 0;
  retailersSnap.forEach(c => { retailerDebt += asNumber(c.val().outstandingDebt || 0); });
  console.log("Retailer Debt:", retailerDebt);

  let collectorCash = 0;
  collectorsSnap.forEach(c => { collectorCash += asNumber(c.val().cashOnHand || 0); });
  console.log("Collector Cash:", collectorCash);

  const totalAssets = bankBalance + vfNumberBalance + retailerDebt + collectorCash;
  const adjustedTotalAssets = totalAssets + totalOutstandingLoans;
  console.log("Adjusted Total Assets:", adjustedTotalAssets);

  const netProfit = adjustedTotalAssets - (openingCapital + totalActiveInvestorCapital);
  console.log("Business Net Profit:", netProfit);

  process.exit(0);
}

debugProfit();
