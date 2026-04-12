const admin = require('firebase-admin');
const {
  asNumber,
  safeDate,
  getMobileNumberBalance,
  getRetailerOutstandingDebt,
  getRetailerInstaPayOutstandingDebt,
  getTransactionTimestampMs,
} = require('./helpers');

const PROFIT_CALCULATION_VERSION = 2;

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

function _computeReconciledProfit(dbData) {
  const openingCapital = asNumber(dbData.openingCapital);
  const totalActiveInvestorCapital = _sumActiveInvestorCapital(dbData.investorsSnap);
  const totalOutstandingLoans = _sumOutstandingLoans(dbData.loansSnap);
  const currentAssets = _computeCurrentAssetTotal(dbData);
  const effectiveStartingCapital = openingCapital + totalActiveInvestorCapital - totalOutstandingLoans;
  const reconciledProfit = currentAssets.currentTotalAssets - effectiveStartingCapital;

  return {
    openingCapital,
    totalActiveInvestorCapital,
    totalOutstandingLoans,
    effectiveStartingCapital,
    ...currentAssets,
    reconciledProfit
  };
}

function _getGlobalAvgBuyPrice(ledgerSnap) {
  let totalBuyEgp = 0;
  let totalBuyUsdt = 0;
  if (ledgerSnap && ledgerSnap.exists()) {
    ledgerSnap.forEach((child) => {
      const tx = child.val();
      if (tx.type === 'BUY_USDT') {
        totalBuyEgp += asNumber(tx.amount);
        totalBuyUsdt += asNumber(tx.usdtQuantity);
      }
    });
  }
  return totalBuyUsdt > 0 ? totalBuyEgp / totalBuyUsdt : 0;
}

function _getGlobalAvgSellPrice(ledgerSnap) {
  let totalSellEgp = 0;
  let totalSellUsdt = 0;
  if (ledgerSnap && ledgerSnap.exists()) {
    ledgerSnap.forEach((child) => {
      const tx = child.val();
      if (tx.type === 'SELL_USDT') {
        totalSellEgp += asNumber(tx.amount);
        totalSellUsdt += asNumber(tx.usdtQuantity);
      }
    });
  }
  return totalSellUsdt > 0 ? totalSellEgp / totalSellUsdt : 0;
}

function _getPerformanceForDateRange(dbData, dateStr, workingDays = 1) {
  const { ledgerSnap, retailersSnap } = dbData;

  // DISTRIBUTE_VFCASH is the true daily VF business volume metric.
  // SELL_USDT / BUY_USDT are kept only for computing avgBuy / avgSell (spread calc).
  let totalDistVf = 0;
  let totalDistVfDebt = 0;

  let totalBuyEgp = 0;
  let totalBuyUsdt = 0;
  let totalSellEgp = 0;
  let totalSellUsdt = 0;
  let buyEntriesCount = 0;
  let sellEntriesCount = 0;

  let totalInstaFlow = 0;
  let totalInstaProfit = 0;
  let totalInstaFees = 0;
  let totalInternalVfFees = 0;
  let totalExternalVfFees = 0;
  let totalExpenses = 0;

  const targetDate = safeDate(dateStr, new Date().toISOString());
  const startDate = new Date(Date.UTC(targetDate.getUTCFullYear(), targetDate.getUTCMonth(), targetDate.getUTCDate()));
  startDate.setUTCDate(startDate.getUTCDate() - (asNumber(workingDays) - 1));
  startDate.setUTCHours(0, 0, 0, 0);

  const endThreshold = new Date(Date.UTC(targetDate.getUTCFullYear(), targetDate.getUTCMonth(), targetDate.getUTCDate()));
  endThreshold.setUTCHours(23, 59, 59, 999);

  const startTs = startDate.getTime();
  const endTs = endThreshold.getTime();

  if (ledgerSnap && ledgerSnap.exists()) {
    ledgerSnap.forEach((child) => {
      const tx = child.val();
      const txTs = getTransactionTimestampMs(tx);
      if (txTs < startTs || txTs > endTs) return;

      if (tx.type === 'BUY_USDT') {
        totalBuyEgp += asNumber(tx.amount);
        totalBuyUsdt += asNumber(tx.usdtQuantity);
        buyEntriesCount += 1;
      } else if (tx.type === 'SELL_USDT') {
        totalSellEgp += asNumber(tx.amount);
        totalSellUsdt += asNumber(tx.usdtQuantity);
        sellEntriesCount += 1;
      } else if (tx.type === 'DISTRIBUTE_VFCASH') {
        totalDistVf += asNumber(tx.amount);
        const debtMatch = (tx.notes || '').match(/Debt \+([0-9.]+)/);
        totalDistVfDebt += debtMatch ? parseFloat(debtMatch[1]) : asNumber(tx.amount);
      } else if (tx.type === 'DISTRIBUTE_INSTAPAY') {
        totalInstaFlow += asNumber(tx.amount);
      } else if (tx.type === 'INSTAPAY_DIST_PROFIT') {
        totalInstaProfit += asNumber(tx.amount);
      } else if (tx.type === 'INTERNAL_VF_TRANSFER_FEE') {
        totalInternalVfFees += asNumber(tx.amount);
      } else if (tx.type === 'EXPENSE_VFCASH_FEE') {
        totalExternalVfFees += asNumber(tx.amount);
      } else if (tx.type === 'EXPENSE_INSTAPAY_FEE') {
        totalInstaFees += asNumber(tx.amount);
      } else if (
        tx.type === 'EXPENSE_BANK' ||
        tx.type === 'EXPENSE_VFNUMBER' ||
        tx.type === 'EXPENSE_COLLECTOR'
      ) {
        totalExpenses += asNumber(tx.amount);
      }
    });
  }

  let outstandingRetailerVfDebt = 0;
  if (retailersSnap && retailersSnap.exists()) {
    retailersSnap.forEach((child) => {
      const r = child.val();
      outstandingRetailerVfDebt += Math.max(0, asNumber(r.totalAssigned) - asNumber(r.totalCollected));
    });
  }

  const avgBuy = totalBuyUsdt > 0 ? totalBuyEgp / totalBuyUsdt : _getGlobalAvgBuyPrice(ledgerSnap);
  const avgSell = totalSellUsdt > 0 ? totalSellEgp / totalSellUsdt : _getGlobalAvgSellPrice(ledgerSnap);

  const rawSpread = avgBuy > 0 && avgSell > 0 ? ((avgSell - avgBuy) / avgBuy) * 1000 : 0;
  const totalVfDiscount = Math.max(0, totalDistVf - totalDistVfDebt);
  const retailerDiscountPer1000 = totalDistVf > 0 ? (totalVfDiscount / totalDistVf) * 1000 : 0;
  const spread = Math.max(0, rawSpread - retailerDiscountPer1000);

  const days = asNumber(workingDays) || 1;
  const vfDailyFlow = totalDistVf / days;
  const instaDailyFlow = totalInstaFlow / days;

  const effectiveVfDist = Math.max(0, totalDistVf - outstandingRetailerVfDebt);
  const vfProfit = totalDistVf > 0 ? Math.max(0, totalDistVf * spread / 1000) / days : 0;

  const systemInstaProfitPer1000 = totalInstaFlow > 0 ? (totalInstaProfit / totalInstaFlow) * 1000 : 0;
  const businessGrossProfit = vfProfit + totalInstaProfit;

  const totalFees = totalInternalVfFees + totalExternalVfFees + totalInstaFees + totalExpenses;
  const businessNetProfit = businessGrossProfit - totalFees;

  return {
    date: formatDateKey(dateStr),
    workingDays: days,
    totalSellAmount: totalDistVf,
    vfDailyFlow,
    totalInstaAmount: totalInstaFlow,
    instaDailyFlow,
    totalDailyFlow: vfDailyFlow + instaDailyFlow,
    totalBuyEgp,
    totalBuyUsdt,
    totalSellEgp,
    totalSellUsdt,
    totalDistVf,
    totalDistVfDebt,
    outstandingRetailerVfDebt,
    effectiveVfDist,
    avgBuy,
    avgSell,
    spread,
    rawSpread,
    retailerDiscountAmount: totalVfDiscount,
    retailerDiscountPer1000,
    buyEntriesCount,
    sellEntriesCount,
    vfProfit,
    instaProfit: totalInstaProfit,
    internalVfFees: totalInternalVfFees,
    externalVfFees: totalExternalVfFees,
    instaFees: totalInstaFees,
    expenses: totalExpenses,
    totalFees,
    systemInstaProfitPer1000,
    businessGrossProfit,
    businessNetProfit
  };
}

function _buildSystemProfitSnapshotForDate(dbData, dateStr) {
  const performance = _getPerformanceForDateRange(dbData, dateStr, 1);
  const reconciliation = _computeReconciledProfit(dbData);

  return {
    ...performance,
    calculationVersion: PROFIT_CALCULATION_VERSION,
    openingCapital: asNumber(dbData.openingCapital),
    effectiveStartingCapital: reconciliation.effectiveStartingCapital,
    currentTotalAssets: reconciliation.currentTotalAssets,
    reconciledProfit: reconciliation.reconciledProfit,
    calculatedAt: Date.now()
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
    const rawNet = asNumber(systemSnapshots[dayKey]?.businessNetProfit);
    operationalProfit += rawNet;
    positiveOperationalProfit += Math.max(0, rawNet);
  });

  const cappedProfit = Math.min(
    Math.max(0, operationalProfit),
    Math.max(0, reconciliation.reconciledProfit)
  );
  const allocationRatio = positiveOperationalProfit > 0 ? (cappedProfit / positiveOperationalProfit) : 0;

  dateKeys.forEach((dayKey) => {
    const rawNet = asNumber(systemSnapshots[dayKey]?.businessNetProfit);
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

function _buildInvestorSnapshotForDate(investor, systemSnapshot, distributableNetProfit, existingSnapshot = null) {
  // Paid snapshots are frozen — recalculating would change the recorded profit amount
  if (existingSnapshot?.isPaid === true &&
      existingSnapshot?.calculationVersion === PROFIT_CALCULATION_VERSION) {
    return existingSnapshot;
  }

  const openingCapital = asNumber(investor.halfCumulativeCapital) > 0
    ? asNumber(investor.halfCumulativeCapital) * 2
    : asNumber(systemSnapshot.openingCapital);
  const vfDailyFlow = asNumber(systemSnapshot.vfDailyFlow);
  const instaDailyFlow = asNumber(systemSnapshot.instaDailyFlow);
  const totalDailyFlow = asNumber(systemSnapshot.totalDailyFlow);
  const hurdle = asNumber(investor.halfCumulativeCapital) > 0
    ? asNumber(investor.halfCumulativeCapital)
    : openingCapital / 2;
  const investorCap = asNumber(investor.investedAmount) / 2;
  const excessFlow = Math.max(0, totalDailyFlow - hurdle);
  const eligibleTotal = Math.min(excessFlow, investorCap);
  const shareFactor = asNumber(investor.profitSharePercent) / 100;
  const flowRatio = totalDailyFlow > 0 ? (eligibleTotal / totalDailyFlow) : 0;
  const investorProfit = Math.max(0, asNumber(distributableNetProfit) * flowRatio * shareFactor);

  const vfFlowRatio = totalDailyFlow > 0 ? (vfDailyFlow / totalDailyFlow) : 0;
  const instaFlowRatio = totalDailyFlow > 0 ? (instaDailyFlow / totalDailyFlow) : 0;
  const vfShare = eligibleTotal * vfFlowRatio;
  const instaShare = eligibleTotal * instaFlowRatio;
  const vfProfit = investorProfit * vfFlowRatio;
  const instaProfit = investorProfit * instaFlowRatio;

  return {
    calculationVersion: PROFIT_CALCULATION_VERSION,
    date: systemSnapshot.date,
    workingDays: 1,
    openingCapital,
    totalLoansOutstanding: 0,
    currentTotalCapital: 0,
    capitalShortfall: Math.max(0, hurdle - totalDailyFlow),
    totalVfCollected: 0,
    totalInstaCollected: 0,
    currentBankBalance: 0,
    usdExchangeEGP: 0,
    retailerVfDebt: 0,
    collectorCash: 0,
    retailerInstaDebt: 0,
    vfRawFlow: asNumber(systemSnapshot.totalSellAmount),
    instaRawFlow: asNumber(systemSnapshot.totalInstaAmount),
    vfDailyFlow: asNumber(systemSnapshot.vfDailyFlow),
    instaDailyFlow: asNumber(systemSnapshot.instaDailyFlow),
    totalDailyFlow,
    halfCumulativeCapital: asNumber(investor.halfCumulativeCapital),
    eligibleTotal,
    vfShare,
    instaShare,
    avgBuyPrice: asNumber(systemSnapshot.avgBuy),
    avgSellPrice: asNumber(systemSnapshot.avgSell),
    buyEntriesCount: asNumber(systemSnapshot.buyEntriesCount),
    sellEntriesCount: asNumber(systemSnapshot.sellEntriesCount),
    vfProfitPer1000: asNumber(systemSnapshot.spread),
    instaProfitPer1000: asNumber(systemSnapshot.systemInstaProfitPer1000),
    totalInstaPayProfit: asNumber(systemSnapshot.instaProfit),
    totalInstaPayVolume: asNumber(systemSnapshot.totalInstaAmount),
    vfProfit,
    instaProfit,
    totalGrossProfit: asNumber(distributableNetProfit),
    investorProfit,
    isPaid: existingSnapshot?.calculationVersion === PROFIT_CALCULATION_VERSION && existingSnapshot?.isPaid === true,
    paidAt: existingSnapshot?.calculationVersion === PROFIT_CALCULATION_VERSION ? (existingSnapshot?.paidAt ?? null) : null,
    paidByUid: existingSnapshot?.calculationVersion === PROFIT_CALCULATION_VERSION ? (existingSnapshot?.paidByUid ?? null) : null,
    calculatedAt: Date.now()
  };
}

function _buildPartnerSnapshotForDate(partner, systemSnapshot, distributableNetProfit, totalInvestorProfitDeducted, existingSnapshot = null) {
  // Paid snapshots are frozen — recalculating would change the recorded profit amount
  if (existingSnapshot?.isPaid === true &&
      existingSnapshot?.calculationVersion === PROFIT_CALCULATION_VERSION) {
    return existingSnapshot;
  }

  const businessNetProfitBeforeInvestors = asNumber(distributableNetProfit);
  const businessNetProfitAfterInvestors = Math.max(0, businessNetProfitBeforeInvestors - asNumber(totalInvestorProfitDeducted));
  const partnerProfit = businessNetProfitAfterInvestors * (asNumber(partner.sharePercent) / 100);

  return {
    calculationVersion: PROFIT_CALCULATION_VERSION,
    date: systemSnapshot.date,
    workingDays: 1,
    vfDailyFlow: asNumber(systemSnapshot.vfDailyFlow),
    instaDailyFlow: asNumber(systemSnapshot.instaDailyFlow),
    totalDistVf: asNumber(systemSnapshot.totalDistVf),
    outstandingRetailerVfDebt: asNumber(systemSnapshot.outstandingRetailerVfDebt),
    effectiveVfDist: asNumber(systemSnapshot.effectiveVfDist),
    systemAvgBuyPrice: asNumber(systemSnapshot.avgBuy),
    systemAvgSellPrice: asNumber(systemSnapshot.avgSell),
    systemVfProfitPer1000: asNumber(systemSnapshot.spread),
    systemInstaProfitPer1000: asNumber(systemSnapshot.systemInstaProfitPer1000),
    businessGrossProfit: asNumber(systemSnapshot.businessGrossProfit),
    totalFees: asNumber(systemSnapshot.totalFees),
    internalVfFees: asNumber(systemSnapshot.internalVfFees),
    externalVfFees: asNumber(systemSnapshot.externalVfFees),
    instaFees: asNumber(systemSnapshot.instaFees),
    totalInvestorProfitDeducted: asNumber(totalInvestorProfitDeducted),
    businessNetProfitBeforeInvestors,
    businessNetProfitAfterInvestors,
    businessNetProfit: businessNetProfitAfterInvestors,
    sharePercent: asNumber(partner.sharePercent),
    partnerProfit,
    isPaid: existingSnapshot?.calculationVersion === PROFIT_CALCULATION_VERSION && existingSnapshot?.isPaid === true,
    paidAt: existingSnapshot?.calculationVersion === PROFIT_CALCULATION_VERSION ? (existingSnapshot?.paidAt ?? null) : null,
    paidByUid: existingSnapshot?.calculationVersion === PROFIT_CALCULATION_VERSION ? (existingSnapshot?.paidByUid ?? null) : null,
    paidFromType: existingSnapshot?.calculationVersion === PROFIT_CALCULATION_VERSION ? (existingSnapshot?.paidFromType ?? null) : null,
    paidFromId: existingSnapshot?.calculationVersion === PROFIT_CALCULATION_VERSION ? (existingSnapshot?.paidFromId ?? null) : null,
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
  _getGlobalAvgBuyPrice,
  _getGlobalAvgSellPrice,
  _getPerformanceForDateRange,
  _buildSystemProfitSnapshotForDate,
  _ensureSystemProfitSnapshots,
  _buildProfitDistributionContext,
  _buildInvestorSnapshotForDate,
  _buildPartnerSnapshotForDate,
};
