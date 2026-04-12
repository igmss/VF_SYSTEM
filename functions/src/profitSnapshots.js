const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { asNumber, requireFinanceRole, getCallerRole, safeDate } = require('./shared/helpers');
const {
  PROFIT_CALCULATION_VERSION,
  formatDateKey,
  getDateKeysForRange,
  isInvestorEligibleForDate,
  _buildSystemProfitSnapshotForDate,
  _ensureSystemProfitSnapshots,
  _buildProfitDistributionContext,
  _buildInvestorSnapshotForDate,
  _buildPartnerSnapshotForDate,
} = require('./shared/profitEngine');

const REGION = 'asia-east1';

exports.calculateSystemProfitSnapshot = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const { date, workingDays } = request.data || {};
  const numWorkingDays = Math.max(1, asNumber(workingDays) || 1);
  if (!date) throw new HttpsError('invalid-argument', 'date is required.');

  const db = admin.database();
  const results = await Promise.all([
    db.ref('system_config/openingCapital').once('value'),
    db.ref('financial_ledger').once('value'),
    db.ref('bank_accounts').once('value'),
    db.ref('usd_exchange').once('value'),
    db.ref('retailers').once('value'),
    db.ref('collectors').once('value'),
    db.ref('loans').orderByChild('status').equalTo('active').once('value'),
    db.ref('system_config/module_start_dates').once('value'),
    db.ref('investors').orderByChild('status').equalTo('active').once('value'),
    db.ref('mobile_numbers').once('value')
  ]);

  const dbData = {
    openingCapital: asNumber(results[0].val()),
    ledgerSnap: results[1],
    banksSnap: results[2],
    usdSnap: results[3],
    retailersSnap: results[4],
    collectorsSnap: results[5],
    loansSnap: results[6],
    moduleDatesSnap: results[7],
    investorsSnap: results[8],
    mobileNumbersSnap: results[9]
  };

  const snapshots = await _ensureSystemProfitSnapshots(db, date, numWorkingDays, dbData);
  const orderedDates = getDateKeysForRange(date, numWorkingDays);
  const distributionContext = _buildProfitDistributionContext(orderedDates, snapshots, dbData);

  let totalBusinessGrossProfit = 0;
  let totalBusinessNetProfit = 0;
  let totalDistributableProfit = 0;
  let totalVfDailyFlow = 0;
  let totalInstaDailyFlow = 0;
  let totalDailyFlow = 0;
  let totalVfProfit = 0;
  let totalInstaProfit = 0;
  let totalInternalVfFees = 0;
  let totalInstaFees = 0;
  let totalExpenses = 0;
  let totalAvgBuy = 0;
  let totalAvgSell = 0;
  let totalSpread = 0;

  orderedDates.forEach((dayKey) => {
    const snapshot = snapshots[dayKey];
    totalBusinessGrossProfit += asNumber(snapshot.businessGrossProfit);
    totalBusinessNetProfit += asNumber(snapshot.businessNetProfit);
    totalDistributableProfit += asNumber(distributionContext.distributableProfitByDate[dayKey]);
    totalVfDailyFlow += asNumber(snapshot.vfDailyFlow);
    totalInstaDailyFlow += asNumber(snapshot.instaDailyFlow);
    totalDailyFlow += asNumber(snapshot.totalDailyFlow);
    totalVfProfit += asNumber(snapshot.vfProfit);
    totalInstaProfit += asNumber(snapshot.instaProfit);
    totalInternalVfFees += asNumber(snapshot.internalVfFees);
    totalInstaFees += asNumber(snapshot.instaFees);
    totalExpenses += asNumber(snapshot.expenses);
    totalAvgBuy += asNumber(snapshot.avgBuy);
    totalAvgSell += asNumber(snapshot.avgSell);
    totalSpread += asNumber(snapshot.spread);
  });

  return {
    success: true,
    date: formatDateKey(date),
    workingDays: orderedDates.length,
    dailySnapshots: snapshots,
    businessGrossProfit: totalBusinessGrossProfit,
    businessNetProfit: totalBusinessNetProfit,
    finalDistributableProfit: totalDistributableProfit,
    operationalProfit: distributionContext.operationalProfit,
    reconciledProfit: distributionContext.reconciledProfit,
    effectiveStartingCapital: distributionContext.effectiveStartingCapital,
    currentTotalAssets: distributionContext.currentTotalAssets,
    vfDailyFlow: totalVfDailyFlow / orderedDates.length,
    instaDailyFlow: totalInstaDailyFlow / orderedDates.length,
    totalDailyFlow: totalDailyFlow / orderedDates.length,
    vfProfit: totalVfProfit,
    instaProfit: totalInstaProfit,
    internalVfFees: totalInternalVfFees,
    instaFees: totalInstaFees,
    expenses: totalExpenses,
    avgBuy: totalAvgBuy / orderedDates.length,
    avgSell: totalAvgSell / orderedDates.length,
    systemVfProfitPer1000: totalSpread / orderedDates.length
  };
});

exports.rebuildProfitSnapshots = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') throw new HttpsError('permission-denied', 'Admin access required.');

  const { startDate, endDate, resetPaidFlags = false } = request.data || {};
  if (!startDate || !endDate) {
    throw new HttpsError('invalid-argument', 'startDate and endDate are required.');
  }

  const db = admin.database();
  const results = await Promise.all([
    db.ref('system_config/openingCapital').once('value'),
    db.ref('system_config/partners').once('value'),
    db.ref('investors').orderByChild('status').equalTo('active').once('value'),
    db.ref('financial_ledger').once('value'),
    db.ref('bank_accounts').once('value'),
    db.ref('usd_exchange').once('value'),
    db.ref('retailers').once('value'),
    db.ref('collectors').once('value'),
    db.ref('loans').orderByChild('status').equalTo('active').once('value'),
    db.ref('system_config/module_start_dates').once('value'),
    db.ref('mobile_numbers').once('value')
  ]);

  const dbData = {
    openingCapital: asNumber(results[0].val()),
    ledgerSnap: results[3],
    banksSnap: results[4],
    usdSnap: results[5],
    retailersSnap: results[6],
    collectorsSnap: results[7],
    loansSnap: results[8],
    moduleDatesSnap: results[9],
    investorsSnap: results[2],
    mobileNumbersSnap: results[10]
  };

  const partnersSnap = results[1];
  const investorsSnap = results[2];
  const start = safeDate(startDate, startDate);
  const end = safeDate(endDate, endDate);

  const normalizedStart = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate()));
  const normalizedEnd = new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate()));
  if (normalizedStart.getTime() > normalizedEnd.getTime()) {
    throw new HttpsError('invalid-argument', 'startDate must be <= endDate.');
  }

  let existingInvestorSnapshots = {};
  let existingPartnerSnapshots = {};
  if (!resetPaidFlags) {
    const [existingInvSnap, existingPartSnap] = await Promise.all([
      db.ref('investor_profit_snapshots').once('value'),
      db.ref('partner_profit_snapshots').once('value'),
    ]);
    existingInvestorSnapshots = existingInvSnap.exists() ? existingInvSnap.val() : {};
    existingPartnerSnapshots = existingPartSnap.exists() ? existingPartSnap.val() : {};
  }

  const updates = {};
  const rebuiltDates = [];
  const dateKeys = [];

  for (
    let cursor = new Date(normalizedStart);
    cursor.getTime() <= normalizedEnd.getTime();
    cursor.setUTCDate(cursor.getUTCDate() + 1)
  ) {
    dateKeys.push(cursor.toISOString().split('T')[0]);
  }

  const systemSnapshots = {};
  dateKeys.forEach((dayKey) => {
    systemSnapshots[dayKey] = _buildSystemProfitSnapshotForDate(dbData, dayKey);
    updates[`system_profit_snapshots/${dayKey}`] = systemSnapshots[dayKey];
  });
  const distributionContext = _buildProfitDistributionContext(dateKeys, systemSnapshots, dbData);

  for (const dayKey of dateKeys) {
    const systemSnapshot = systemSnapshots[dayKey];
    const investorProfitByDate = {};
    if (investorsSnap.exists()) {
      investorsSnap.forEach((child) => {
        const investorId = child.key;
        const investor = child.val();
        if (investor.status !== 'active') return;
        if (!isInvestorEligibleForDate(investor, dayKey)) return;

        const existingInvSnap = resetPaidFlags ? null : (existingInvestorSnapshots[investorId]?.[dayKey] || null);
        const dailyInvestorSnapshot = _buildInvestorSnapshotForDate(
          investor,
          systemSnapshot,
          distributionContext.distributableProfitByDate[dayKey] || 0,
          existingInvSnap
        );
        investorProfitByDate[dayKey] = (investorProfitByDate[dayKey] || 0) + asNumber(dailyInvestorSnapshot.investorProfit);
        updates[`investor_profit_snapshots/${investorId}/${dayKey}`] = dailyInvestorSnapshot;
      });
    }

    if (partnersSnap.exists()) {
      partnersSnap.forEach((child) => {
        const partnerId = child.key;
        const partner = child.val();
        if (partner.status !== 'active' && partner.status !== undefined) return;

        const existingPartSnap = resetPaidFlags ? null : (existingPartnerSnapshots[partnerId]?.[dayKey] || null);
        const partnerSnapshot = _buildPartnerSnapshotForDate(
          partner,
          systemSnapshot,
          distributionContext.distributableProfitByDate[dayKey] || 0,
          asNumber(investorProfitByDate[dayKey] || 0),
          existingPartSnap
        );
        updates[`partner_profit_snapshots/${partnerId}/${dayKey}`] = partnerSnapshot;
      });
    }

    rebuiltDates.push(dayKey);
  }

  await db.ref().update(updates);
  return { success: true, rebuiltDates, count: rebuiltDates.length, calculationVersion: PROFIT_CALCULATION_VERSION };
});
