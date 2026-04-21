const admin = require('firebase-admin');
const {
  asNumber,
  safeDate,
  getMobileNumberBalance,
  getRetailerOutstandingDebt,
  getRetailerInstaPayOutstandingDebt,
  getTransactionTimestampMs,
} = require('./helpers');

const PROFIT_CALCULATION_VERSION = 3.1;

function formatDateKey(dateInput) {
  const parsed = safeDate(dateInput, new Date().toISOString());
  const normalized = new Date(Date.UTC(
    parsed.getUTCFullYear(),
    parsed.getUTCMonth(),
    parsed.getUTCDate()
  ));
  return normalized.toISOString().split('T')[0];
}

function getDateKeysForRange(dateStr, workingDays = 1) {
  const targetDate = safeDate(dateStr, new Date().toISOString());
  const normalizedTarget = new Date(Date.UTC(
    targetDate.getUTCFullYear(),
    targetDate.getUTCMonth(),
    targetDate.getUTCDate()
  ));
  const numDays = Math.max(1, asNumber(workingDays) || 1);
  const dates = [];

  for (let i = 0; i < numDays; i++) {
    const d = new Date(normalizedTarget);
    d.setUTCDate(normalizedTarget.getUTCDate() - i);
    dates.push(d.toISOString().split('T')[0]);
  }

  return dates;
}

function isInvestorEligibleForDate(investor, dayKey) {
  const startDateValue = investor?.investmentDate;
  if (!startDateValue) return true;
  const investorStart = formatDateKey(startDateValue);
  return dayKey >= investorStart;
}

function _sumActiveInvestorCapital(investorsSnap) {
  let total = 0;
  if (investorsSnap && investorsSnap.exists()) {
    investorsSnap.forEach((child) => {
      if (child.val()?.status === 'active') {
        total += asNumber(child.val().investedAmount);
      }
    });
  }
  return total;
}

function _sumOutstandingLoans(loansSnap) {
  let total = 0;
  if (loansSnap && loansSnap.exists()) {
    loansSnap.forEach((child) => {
      const ln = child.val();
      total += Math.max(0, asNumber(ln.principalAmount) - asNumber(ln.amountRepaid));
    });
  }
  return total;
}

function _computeCurrentAssetTotal(dbData) {
  const { banksSnap, retailersSnap, collectorsSnap, mobileNumbersSnap, usdSnap } = dbData;
  let bankBalance = 0;
  let vfNumberBalance = 0;
  let retailerDebt = 0;
  let retailerInstaDebt = 0;
  let collectorCash = 0;
  let usdExchangeEgp = 0;

  if (banksSnap && banksSnap.exists()) {
    banksSnap.forEach((child) => {
      bankBalance += asNumber(child.val().balance);
    });
  }

  if (mobileNumbersSnap && mobileNumbersSnap.exists()) {
    mobileNumbersSnap.forEach((child) => {
      vfNumberBalance += getMobileNumberBalance(child.val());
    });
  }

  if (retailersSnap && retailersSnap.exists()) {
    retailersSnap.forEach((child) => {
      const retailer = child.val();
      retailerDebt += getRetailerOutstandingDebt(retailer);
      retailerInstaDebt += getRetailerInstaPayOutstandingDebt(retailer);
    });
  }

  if (collectorsSnap && collectorsSnap.exists()) {
    collectorsSnap.forEach((child) => {
      collectorCash += asNumber(child.val().cashOnHand);
    });
  }

  // Include USDT held in exchange at last known price — this is real capital in the loop
  if (usdSnap && usdSnap.exists() && usdSnap.val()) {
    const usdData = usdSnap.val();
    const usdtBalance = asNumber(usdData.usdtBalance ?? usdData.balance ?? usdData.usdt);
    const lastPrice = asNumber(usdData.lastPrice ?? usdData.price ?? usdData.egpPrice);
    if (usdtBalance > 0 && lastPrice > 0) {
      usdExchangeEgp = usdtBalance * lastPrice;
    }
  }

  return {
    bankBalance,
    vfNumberBalance,
    retailerDebt,
    retailerInstaDebt,
    collectorCash,
    usdExchangeEgp,
    currentTotalAssets: bankBalance + vfNumberBalance + retailerDebt + retailerInstaDebt + collectorCash + usdExchangeEgp
  };
}

function _computeReconciledProfit(dbData, totalDistributions = 0) {
  const openingCapital = asNumber(dbData.openingCapital);
  const totalActiveInvestorCapital = _sumActiveInvestorCapital(dbData.investorsSnap);
  const totalOutstandingLoans = _sumOutstandingLoans(dbData.loansSnap);
  const currentAssets = _computeCurrentAssetTotal(dbData);
  
  // Total capital injected into the business (Startup funds + Investors)
  const effectiveStartingCapital = openingCapital + totalActiveInvestorCapital;
  
  // Adjusted Assets = Cash in Banks + Wallet Balances + Collector Cash + Retailer Debts + Outstanding Loans + Money already paid out
  const adjustedTotalAssets = currentAssets.currentTotalAssets + totalOutstandingLoans + asNumber(totalDistributions);
  
  // Net Profit is the lifetime growth of business assets over the total invested capital
  const reconciledProfit = adjustedTotalAssets - effectiveStartingCapital;

  return {
    openingCapital,
    totalActiveInvestorCapital,
    totalOutstandingLoans,
    effectiveStartingCapital,
    totalDistributions: asNumber(totalDistributions),
    ...currentAssets,
    adjustedTotalAssets,
    netProfit: reconciledProfit, // Now represents Lifetime Growth
    reconciledProfit
  };
}

/**
 * Calculates earnings for an investor based on the NEW fixed rate logic (V4.0)
 * VF: 7 per 1,000 | InstaPay: 5 per 1,000
 * Only on flow exceeding the waterfall hurdle.
 */
function _calculateInvestorEarningsFixedRate(investor, vfFlow, instaFlow, precedingCapital, openingCapital) {
  const hurdle = (asNumber(openingCapital) / 2) + asNumber(precedingCapital);
  
  const totalFlow = asNumber(vfFlow) + asNumber(instaFlow);
  const excessFlow = Math.max(0, totalFlow - hurdle);
  
  if (excessFlow <= 0) return { investorProfit: 0, vfProfit: 0, instaProfit: 0, hurdle, excessFlow: 0 };

  // Calculate proportional excess for each channel
  const vfRatio = totalFlow > 0 ? asNumber(vfFlow) / totalFlow : 0;
  const instaRatio = totalFlow > 0 ? asNumber(instaFlow) / totalFlow : 0;
  
  const vfExcess = excessFlow * vfRatio;
  const instaExcess = excessFlow * instaRatio;
  
  // V4.0 rates
  const baseVfProfit = (vfExcess / 1000) * 7;
  const baseInstaProfit = (instaExcess / 1000) * 5;
  
  // Apply investor's share % (V4.3)
  const shareFactor = asNumber(investor.profitSharePercent) / 100;
  const vfProfit = baseVfProfit * shareFactor;
  const instaProfit = baseInstaProfit * shareFactor;
  
  return {
    investorProfit: vfProfit + instaProfit,
    vfProfit,
    instaProfit,
    baseVfProfit,
    baseInstaProfit,
    hurdle,
    excessFlow,
    vfExcess,
    instaExcess
  };
}

function _getDailyAvgBuyPrice(ledgerSnap, targetTs) {
  let dailyBuyEgp = 0;
  let dailyBuyUsdt = 0;
  
  const targetDate = new Date(targetTs).toISOString().split('T')[0];
  
  // First pass: Try to find average for the specific day
  if (ledgerSnap && ledgerSnap.exists()) {
    ledgerSnap.forEach((child) => {
      const tx = child.val();
      if (tx.type === 'BUY_USDT') {
        const txDate = new Date(getTransactionTimestampMs(tx)).toISOString().split('T')[0];
        if (txDate === targetDate) {
          dailyBuyEgp += asNumber(tx.amount);
          dailyBuyUsdt += asNumber(tx.usdtQuantity);
        }
      }
    });
  }

  if (dailyBuyUsdt > 0) return dailyBuyEgp / dailyBuyUsdt;

  // Fallback: Find the most recent buy before this day
  let bestTs = 0;
  let fallbackPrice = 53.52; // Safety default based on historical data

  if (ledgerSnap && ledgerSnap.exists()) {
    ledgerSnap.forEach((child) => {
      const tx = child.val();
      if (tx.type === 'BUY_USDT') {
        const txTs = getTransactionTimestampMs(tx);
        if (txTs < targetTs && txTs > bestTs) {
          const qty = asNumber(tx.usdtQuantity);
          if (qty > 0) {
            fallbackPrice = asNumber(tx.amount) / qty;
            bestTs = txTs;
          }
        }
      }
    });
  }
  
  return fallbackPrice;
}

function _getPerformanceForDateRange(dbData, dateStr, workingDays = 1) {
  const { ledgerSnap } = dbData;
  const numDays = asNumber(workingDays) || 1;

  // Date Range Setup
  const targetDate = safeDate(dateStr, new Date().toISOString());
  const startDate = new Date(Date.UTC(targetDate.getUTCFullYear(), targetDate.getUTCMonth(), targetDate.getUTCDate()));
  startDate.setUTCDate(startDate.getUTCDate() - (numDays - 1));
  startDate.setUTCHours(0, 0, 0, 0);

  const endThreshold = new Date(Date.UTC(targetDate.getUTCFullYear(), targetDate.getUTCMonth(), targetDate.getUTCDate()));
  endThreshold.setUTCHours(23, 59, 59, 999);

  const startTs = startDate.getTime();
  const endTs = endThreshold.getTime();

  // Calculate Daily Average Buy Price (Direct Daily Mode)
  const dailyAvgBuyPrice = _getDailyAvgBuyPrice(ledgerSnap, endTs);

  // PASS 2: Accumulate performance metrics for the date range
  let totalVfDistributed = 0;
  let totalInstaDistributed = 0;
  let totalSellEgp = 0;
  let totalSellUsdt = 0;
  let vfDepositProfit = 0;
  let vfDiscountCost = 0;
  let vfFeeCost = 0;
  let instaGrossProfit = 0;
  let instaFeeCost = 0;
  let generalExpenses = 0;
  let sellEntriesCount = 0;
  let buyEntriesRangeCount = 0;

  if (ledgerSnap && ledgerSnap.exists()) {
    ledgerSnap.forEach((child) => {
      const tx = child.val();
      const txTs = getTransactionTimestampMs(tx);
      const isWithinRange = txTs >= startTs && txTs <= endTs;

      if (!isWithinRange) return;

      if (tx.type === 'SELL_USDT') {
        totalSellEgp += asNumber(tx.amount);
        totalSellUsdt += asNumber(tx.usdtQuantity);
        sellEntriesCount++;
      } else if (tx.type === 'BUY_USDT') {
        buyEntriesRangeCount++;
      } else if (tx.type === 'DISTRIBUTE_VFCASH') {
        const amount = asNumber(tx.amount);
        totalVfDistributed += amount;
        const debtMatch = (tx.notes || '').match(/Debt \+([0-9.]+)/);
        const debtAmount = debtMatch ? parseFloat(debtMatch[1]) : amount;
        const discount = amount - debtAmount;
        if (discount > 0) vfDiscountCost += discount;
      } else if (tx.type === 'DISTRIBUTE_INSTAPAY') {
        totalInstaDistributed += asNumber(tx.amount);
      } else if (tx.type === 'INSTAPAY_DIST_PROFIT') {
        instaGrossProfit += asNumber(tx.amount);
      } else if (tx.type === 'VFCASH_RETAIL_PROFIT') {
        vfDepositProfit += asNumber(tx.amount);
      } else if (tx.type === 'INTERNAL_VF_TRANSFER_FEE' || tx.type === 'EXPENSE_VFCASH_FEE') {
        vfFeeCost += asNumber(tx.amount);
      } else if (tx.type === 'EXPENSE_INSTAPAY_FEE') {
        instaFeeCost += asNumber(tx.amount);
      } else if (tx.type === 'EXPENSE_BANK') {
        // As per user audit, only EXPENSE_BANK counts as general expenses (salaries/rent).
        // Fees are already included in net calculations below.
        generalExpenses += asNumber(tx.amount);
      }
    });
  }

  // Calculate Final Metrics
  const vfSpreadProfit = totalSellEgp - (totalSellUsdt * dailyAvgBuyPrice);
  const vfNetProfit = vfSpreadProfit + vfDepositProfit - vfDiscountCost - vfFeeCost;
  const instaNetProfit = instaGrossProfit - instaFeeCost;
  const totalNetProfit = vfNetProfit + instaNetProfit - generalExpenses;

  const vfNetPer1000 = totalVfDistributed > 0 ? (vfNetProfit / totalVfDistributed) * 1000 : 0;
  const instaNetPer1000 = totalInstaDistributed > 0 ? (instaNetProfit / totalInstaDistributed) * 1000 : 0;

  return {
    date: formatDateKey(dateStr),
    workingDays: numDays,
    
    // Performance Summary
    vfNetProfit,
    instaNetProfit,
    totalNetProfit,
    vfNetPer1000,
    instaNetPer1000,
    totalFlow: totalVfDistributed + totalInstaDistributed,

    // Daily Flow Fields
    totalVfDistributed,
    totalInstaDistributed,
    
    // Detailed Breakdown
    dailyAvgBuyPrice, // Renamed for clarity in logic, but keeping backward compatibility if needed:
    globalAvgBuyPrice: dailyAvgBuyPrice, 
    vfSpreadProfit,
    vfDepositProfit,
    vfDiscountCost,
    vfFeeCost,
    instaGrossProfit,
    instaFeeCost,
    generalExpenses,
    
    // Audit Tracking
    totalSellUsdt,
    totalSellEgp,
    sellEntriesCount,
    buyEntriesRangeCount,
    calculatedAt: Date.now()
  };
}


function _buildSystemProfitSnapshotForDate(dbData, dateStr) {
  const performance = _getPerformanceForDateRange(dbData, dateStr, 1);
  const state = _computeReconciledProfit(dbData);

  return {
    ...performance,
    openingCapital: state.openingCapital,
    effectiveStartingCapital: state.effectiveStartingCapital,
    totalOutstandingLoans: state.totalOutstandingLoans,
    currentTotalAssets: state.currentTotalAssets,
    bankBalance: state.bankBalance,
    vfNumberBalance: state.vfNumberBalance,
    retailerDebt: state.retailerDebt,
    retailerInstaDebt: state.retailerInstaDebt,
    collectorCash: state.collectorCash,
    usdExchangeEGP: state.usdExchangeEgp,
    adjustedTotalAssets: state.adjustedTotalAssets,
    reconciledProfit: state.reconciledProfit,
    calculationVersion: PROFIT_CALCULATION_VERSION,
  };
}

async function _ensureSystemProfitSnapshots(db, dateStr, workingDays, dbData) {
  const dates = getDateKeysForRange(dateStr, workingDays);
  const updates = {};
  const snapshots = {};

  dates.forEach((dayKey) => {
    const snapshot = _buildSystemProfitSnapshotForDate(dbData, dayKey);
    snapshots[dayKey] = snapshot;
    updates[`system_profit_snapshots/${dayKey}`] = snapshot;
  });

  if (Object.keys(updates).length > 0) {
    await db.ref().update(updates);
  }

  return snapshots;
}

function _buildProfitDistributionContext(dateKeys, systemSnapshots, dbData) {
  const reconciliation = _computeReconciledProfit(dbData);
  let operationalProfit = 0;
  let positiveOperationalProfit = 0;
  const distributableProfitByDate = {};

  dateKeys.forEach((dayKey) => {
    const rawNet = asNumber(systemSnapshots[dayKey]?.totalNetProfit);
    operationalProfit += rawNet;
    positiveOperationalProfit += Math.max(0, rawNet);
  });

  const cappedProfit = Math.min(
    Math.max(0, operationalProfit),
    Math.max(0, reconciliation.reconciledProfit)
  );
  const allocationRatio = positiveOperationalProfit > 0 ? (cappedProfit / positiveOperationalProfit) : 0;

  dateKeys.forEach((dayKey) => {
    const rawNet = asNumber(systemSnapshots[dayKey]?.totalNetProfit);
    distributableProfitByDate[dayKey] = Math.max(0, rawNet) * allocationRatio;
  });

  return {
    ...reconciliation,
    operationalProfit,
    positiveOperationalProfit,
    finalDistributableProfit: cappedProfit,
    allocationRatio,
    distributableProfitByDate
  };
}

function _buildInvestorSnapshotForDate(
  investor,
  systemSnapshot,
  precedingCapital,
  openingCapital,
  existingSnapshot = null
) {
  // Paid snapshots are historical records and must stay frozen.
  if (existingSnapshot?.isPaid === true) {
    return existingSnapshot;
  }

  const hurdle = (asNumber(openingCapital) / 2) + asNumber(precedingCapital);
  const totalFlow = asNumber(systemSnapshot.totalFlow);
  const vfFlow = asNumber(systemSnapshot.totalVfDistributed);
  const instaFlow = asNumber(systemSnapshot.totalInstaDistributed);

  let investorProfit = 0;
  let vfInvestorProfit = 0;
  let instaInvestorProfit = 0;
  let excess = 0;
  let vfExcess = 0;
  let instaExcess = 0;

  if (totalFlow > hurdle) {
    excess = totalFlow - hurdle;
    vfExcess = excess * (totalFlow > 0 ? (vfFlow / totalFlow) : 0);
    instaExcess = excess * (totalFlow > 0 ? (instaFlow / totalFlow) : 0);

    const vfNetPer1000 = Math.max(0, asNumber(systemSnapshot.vfNetPer1000));
    const instaNetPer1000 = Math.max(0, asNumber(systemSnapshot.instaNetPer1000));
    const shareFactor = asNumber(investor.profitSharePercent) / 100;

    vfInvestorProfit = (vfExcess / 1000) * vfNetPer1000 * shareFactor;
    instaInvestorProfit = (instaExcess / 1000) * instaNetPer1000 * shareFactor;
    investorProfit = vfInvestorProfit + instaInvestorProfit;
  }

  return {
    calculationVersion: PROFIT_CALCULATION_VERSION,
    date: systemSnapshot.date,
    workingDays: 1,
    hurdle,
    precedingCapital,
    excess,
    vfExcess,
    instaExcess,
    vfNetPer1000: asNumber(systemSnapshot.vfNetPer1000),
    instaNetPer1000: asNumber(systemSnapshot.instaNetPer1000),
    vfInvestorProfit,
    instaInvestorProfit,
    investorProfit,
    totalFlow,
    vfFlow,
    instaFlow,
    profitSharePercent: asNumber(investor.profitSharePercent),
    
    // Audit / State Snapshot (V3.1 Clean Return)
    openingCapital: asNumber(openingCapital),
    totalLoansOutstanding: asNumber(systemSnapshot.totalOutstandingLoans),
    currentTotalAssets: asNumber(systemSnapshot.currentTotalAssets),
    reconciledProfit: asNumber(systemSnapshot.reconciledProfit),
    currentBankBalance: asNumber(systemSnapshot.bankBalance),
    usdExchangeEGP: asNumber(systemSnapshot.usdExchangeEGP),
    retailerVfDebt: asNumber(systemSnapshot.retailerDebt),
    collectorCash: asNumber(systemSnapshot.collectorCash),
    retailerInstaDebt: asNumber(systemSnapshot.retailerInstaDebt),
    globalAvgBuyPrice: asNumber(systemSnapshot.globalAvgBuyPrice),
    totalNetProfit: asNumber(systemSnapshot.totalNetProfit), 
    
    isPaid: existingSnapshot?.isPaid === true,
    paidAt: existingSnapshot?.paidAt ?? null,
    paidByUid: existingSnapshot?.paidByUid ?? null,
    calculatedAt: Date.now()
  };
}

function _buildPartnerSnapshotForDate(partner, systemSnapshot, totalInvestorProfitDeducted, existingSnapshot = null, allocationRatio = 1) {
  const totalNetProfit = asNumber(systemSnapshot.totalNetProfit);
  const reconciledPool = Math.max(0, totalNetProfit * asNumber(allocationRatio));
  const remainingForPartners = Math.max(0, reconciledPool - asNumber(totalInvestorProfitDeducted));
  const partnerProfit = remainingForPartners * (asNumber(partner.sharePercent) / 100);

  return {
    calculationVersion: PROFIT_CALCULATION_VERSION,
    date: systemSnapshot.date,
    workingDays: 1,
    
    // Core Distribution
    totalNetProfit,
    allocationRatio: asNumber(allocationRatio),
    reconciledPool,
    totalInvestorProfitDeducted,
    remainingForPartners,
    partnerProfit,
    sharePercent: asNumber(partner.sharePercent),
    
    // V3.1 Performance Breakdown (Direct from systemSnapshot)
    vfSpreadProfit: asNumber(systemSnapshot.vfSpreadProfit),
    vfDepositProfit: asNumber(systemSnapshot.vfDepositProfit),
    vfDiscountCost: asNumber(systemSnapshot.vfDiscountCost),
    vfFeeCost: asNumber(systemSnapshot.vfFeeCost),
    vfNetProfit: asNumber(systemSnapshot.vfNetProfit),
    vfNetPer1000: asNumber(systemSnapshot.vfNetPer1000),
    
    instaGrossProfit: asNumber(systemSnapshot.instaGrossProfit),
    instaFeeCost: asNumber(systemSnapshot.instaFeeCost),
    instaNetProfit: asNumber(systemSnapshot.instaNetProfit),
    instaNetPer1000: asNumber(systemSnapshot.instaNetPer1000),
    
    generalExpenses: asNumber(systemSnapshot.generalExpenses),
    globalAvgBuyPrice: asNumber(systemSnapshot.globalAvgBuyPrice),
    
    // Flow Metrics
    vfDailyFlow: asNumber(systemSnapshot.totalVfDistributed),
    instaDailyFlow: asNumber(systemSnapshot.totalInstaDistributed),
    totalDailyFlow: asNumber(systemSnapshot.totalFlow),
    totalVfDistributed: asNumber(systemSnapshot.totalVfDistributed),
    totalInstaDistributed: asNumber(systemSnapshot.totalInstaDistributed),

    isPaid: existingSnapshot?.isPaid === true,
    paidAt: existingSnapshot?.paidAt ?? null,
    paidByUid: existingSnapshot?.paidByUid ?? null,
    paidFromType: existingSnapshot?.paidFromType ?? null,
    paidFromId: existingSnapshot?.paidFromId ?? null,
    calculatedAt: Date.now()
  };
}

module.exports = {
  PROFIT_CALCULATION_VERSION,
  formatDateKey,
  getDateKeysForRange,
  isInvestorEligibleForDate,
  _sumActiveInvestorCapital,
  _sumOutstandingLoans,
  _computeCurrentAssetTotal,
  _computeReconciledProfit,
  _calculateInvestorEarningsFixedRate,
  _getPerformanceForDateRange,
  _buildSystemProfitSnapshotForDate,
  _ensureSystemProfitSnapshots,
  _buildProfitDistributionContext,
  _buildInvestorSnapshotForDate,
  _buildPartnerSnapshotForDate,
};
