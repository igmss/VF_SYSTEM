const admin = require('firebase-admin');

async function fullAudit() {
  if (!admin.apps.length) {
    admin.initializeApp({
      databaseURL: "https://vodatracking-default-rtdb.firebaseio.com"
    });
  }
  const db = admin.database();

  const [
    configSnap,
    partnersSnap,
    investorsSnap,
    banksSnap,
    usdSnap,
    retailersSnap,
    collectorsSnap,
    loansSnap,
    flowSnap,
    mobileNumbersSnap
  ] = await Promise.all([
    db.ref('system_config/openingCapital').once('value'),
    db.ref('system_config/partners').once('value'),
    db.ref('investors').once('value'),
    db.ref('bank_accounts').once('value'),
    db.ref('usd_exchange').once('value'),
    db.ref('retailers').once('value'),
    db.ref('collectors').once('value'),
    db.ref('loans').once('value'),
    db.ref('system_config/module_start_dates').once('value'),
    db.ref('summary/daily_flow').once('value'),
    db.ref('mobile_numbers').once('value')
  ]);

  const asNumber = v => parseFloat(v) || 0;

  console.log("=== CAPITAL ===");
  const openingCapital = asNumber(configSnap.val());
  console.log("Opening Capital (Partners):", openingCapital);

  let totalInvestorCapital = 0;
  investorsSnap.forEach(c => {
    const i = c.val();
    if (i.status === 'active') {
       totalInvestorCapital += asNumber(i.investedAmount);
       console.log(`- Investor ${i.name}: ${i.investedAmount}`);
    }
  });
  console.log("Total Investor Capital:", totalInvestorCapital);

  console.log("\n=== ASSETS (CASH/WALLETS) ===");
  let bankTotal = 0;
  banksSnap.forEach(c => {
    bankTotal += asNumber(c.val().balance);
    console.log(`- Bank ${c.val().bankName}: ${c.val().balance}`);
  });

  let vfTotal = 0;
  mobileNumbersSnap.forEach(c => {
    const n = c.val();
    // V4.0 Calculation from helpers.js: initialBalance + inTotalUsed - outTotalUsed
    const bal = asNumber(n.initialBalance) + asNumber(n.inTotalUsed) - asNumber(n.outTotalUsed);
    vfTotal += bal;
    // console.log(`- VF ${n.phoneNumber}: ${bal}`);
  });
  console.log("Total VF Wallets:", vfTotal);

  let collectorTotal = 0;
  collectorsSnap.forEach(c => {
    collectorTotal += asNumber(c.val().cashOnHand);
    console.log(`- Collector ${c.val().name}: ${c.val().cashOnHand}`);
  });

  let retailerTotal = 0;
  retailersSnap.forEach(c => {
    const r = c.val();
    const debt = (asNumber(r.totalAssigned) - asNumber(r.totalCollected)) + 
                 (asNumber(r.instaPayTotalAssigned) - asNumber(r.instaPayTotalCollected));
    retailerTotal += Math.max(0, debt);
  });
  console.log("Total Retailer Debt:", retailerTotal);

  let usdEgp = 0;
  if (usdSnap.exists()) {
    const u = usdSnap.val();
    const balance = asNumber(u.usdtBalance ?? u.balance);
    const price = asNumber(u.lastPrice ?? u.egpPrice);
    usdEgp = balance * price;
    console.log(`- USD Exchange: ${balance} USDT @ ${price} = ${usdEgp} EGP`);
  }

  console.log("\n=== ASSETS (LOANS) ===");
  let loanTotal = 0;
  loansSnap.forEach(c => {
    const l = c.val();
    if (l.status === 'active') {
      const remaining = asNumber(l.principalAmount) - asNumber(l.amountRepaid);
      loanTotal += Math.max(0, remaining);
    }
  });
  console.log("Total Outstanding Loans:", loanTotal);

  const currentAssets = bankTotal + vfTotal + collectorTotal + retailerTotal + usdEgp;
  const totalAssetsWithLoans = currentAssets + loanTotal;

  console.log("\n=== FINAL PROFIT RECONCILIATION ===");
  console.log("Total Assets (Cash/Val):", currentAssets);
  console.log("Adjusted Assets (incl Loans):", totalAssetsWithLoans);
  
  const netProfitModelA = totalAssetsWithLoans - (openingCapital + totalInvestorCapital);
  console.log("Net Profit (After All Capital):", netProfitModelA);

  const netProfitModelB = totalAssetsWithLoans - openingCapital;
  console.log("Net Profit (Only Partners Capital):", netProfitModelB);

  process.exit(0);
}

fullAudit();
