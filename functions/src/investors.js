const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { v4: uuidv4 } = require('uuid');
const { asNumber, requireFinanceRole, getCallerRole } = require('./shared/helpers');
const {
  formatDateKey,
  getDateKeysForRange,
  isInvestorEligibleForDate,
  _ensureSystemProfitSnapshots,
  _buildProfitDistributionContext,
  _buildInvestorSnapshotForDate,
} = require('./shared/profitEngine');

const REGION = 'asia-east1';

exports.recordInvestorCapital = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') throw new HttpsError('permission-denied', 'Only admins can record investor capital.');

  const { name, phone, investedAmount, initialBusinessCapital, profitSharePercent, investmentDate, periodDays, bankAccountId, notes, createdByUid } = request.data;
  const numAmount = asNumber(investedAmount);
  const numShare = asNumber(profitSharePercent);

  if (numAmount <= 0) throw new HttpsError('invalid-argument', 'Invested amount must be > 0.');
  if (numShare < 1 || numShare > 100) throw new HttpsError('invalid-argument', 'Profit share percent must be between 1 and 100.');

  const db = admin.database();

  const investorsSnap = await db.ref('investors').orderByChild('status').equalTo('active').once('value');
  let priorInvestorsCapital = 0;
  if (investorsSnap.exists()) {
    investorsSnap.forEach((child) => {
      priorInvestorsCapital += asNumber(child.val().investedAmount);
    });
  }

  const numInitialBusinessCapital = asNumber(initialBusinessCapital);
  const halfInvestedAmount = numAmount / 2;
  const cumulativeCapitalBefore = numInitialBusinessCapital + priorInvestorsCapital;
  const halfCumulativeCapital = cumulativeCapitalBefore / 2;

  const bankRef = db.ref(`bank_accounts/${bankAccountId}`);
  const bankSnap = await bankRef.once('value');
  if (!bankSnap.exists()) throw new HttpsError('not-found', 'Bank account not found.');
  const bankName = bankSnap.val().bankName || 'Bank Account';

  const balanceResult = await bankRef.child('balance').transaction((current) => {
    if (current === null) return current;
    return asNumber(current) + numAmount;
  });

  if (!balanceResult.committed) {
    throw new HttpsError('internal', 'Failed to update bank balance.');
  }

  const investorId = uuidv4();
  const txId = uuidv4();
  const nowTs = Date.now();

  const investorRecord = {
    id: investorId,
    name: name || 'Investor',
    phone: phone || '',
    investedAmount: numAmount,
    halfInvestedAmount: halfInvestedAmount,
    initialBusinessCapital: numInitialBusinessCapital,
    cumulativeCapitalBefore: cumulativeCapitalBefore,
    halfCumulativeCapital: halfCumulativeCapital,
    profitSharePercent: numShare,
    investmentDate: investmentDate,
    periodDays: asNumber(periodDays) || 30,
    status: 'active',
    totalProfitPaid: 0,
    notes: notes || null,
    createdByUid: createdByUid || uid,
    createdAt: nowTs,
  };

  const updates = {};
  updates[`investors/${investorId}`] = investorRecord;
  updates[`financial_ledger/${txId}`] = {
    id: txId,
    type: 'INVESTOR_CAPITAL_IN',
    amount: numAmount,
    toId: bankAccountId,
    toLabel: bankName,
    fromLabel: investorRecord.name,
    notes: `Investor capital deposit from ${investorRecord.name}`,
    createdByUid: createdByUid || uid,
    timestamp: nowTs,
  };

  await db.ref().update(updates);

  return { success: true, investorId, halfCumulativeCapital };
});

exports.calculateInvestorDailyProfit = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const { investorId, date, workingDays } = request.data;
  const numWorkingDays = asNumber(workingDays);
  if (numWorkingDays <= 0) throw new HttpsError('invalid-argument', 'workingDays must be > 0.');

  const db = admin.database();
  const investorSnap = await db.ref(`investors/${investorId}`).once('value');
  if (!investorSnap.exists()) throw new HttpsError('not-found', 'Investor not found.');
  const investor = investorSnap.val();
  if (investor.status !== 'active') throw new HttpsError('failed-precondition', 'Investor is not active.');

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

  const systemSnapshots = await _ensureSystemProfitSnapshots(db, date, numWorkingDays, dbData);
  const dateKeys = getDateKeysForRange(date, numWorkingDays)
    .filter((dayKey) => isInvestorEligibleForDate(investor, dayKey));
  const updates = {};

  if (dateKeys.length === 0) {
    throw new HttpsError(
      'failed-precondition',
      `Selected range is before investor start date ${investor.investmentDate}.`
    );
  }
  const distributionContext = _buildProfitDistributionContext(dateKeys, systemSnapshots, dbData);

  let aggregateInvestorProfit = 0;
  let aggregateEligibleTotal = 0;
  let aggregateVfShare = 0;
  let aggregateInstaShare = 0;
  let aggregateVfProfit = 0;
  let aggregateInstaProfit = 0;
  let aggregateGrossProfit = 0;
  let aggregateVfDailyFlow = 0;
  let aggregateInstaDailyFlow = 0;
  let aggregateTotalDailyFlow = 0;
  let aggregateVfRawFlow = 0;
  let aggregateInstaRawFlow = 0;
  let aggregateInstaPayProfit = 0;
  let aggregateInstaPayVolume = 0;
  let aggregateCapitalShortfall = 0;
  let aggregateBuyEntries = 0;
  let aggregateSellEntries = 0;
  let aggregateAvgBuyWeighted = 0;
  let aggregateAvgSellWeighted = 0;
  let aggregateVfProfitPer1000Weighted = 0;
  let aggregateInstaProfitPer1000Weighted = 0;
  let firstDailySnapshot = null;

  for (const dayKey of dateKeys) {
    const systemSnapshot = systemSnapshots[dayKey];
    const existingSnap = await db.ref(`investor_profit_snapshots/${investorId}/${dayKey}`).once('value');
    const dailyInvestorSnapshot = _buildInvestorSnapshotForDate(
      investor,
      systemSnapshot,
      distributionContext.distributableProfitByDate[dayKey] || 0,
      existingSnap.exists() ? existingSnap.val() : null
    );

    updates[`investor_profit_snapshots/${investorId}/${dayKey}`] = dailyInvestorSnapshot;

    if (!firstDailySnapshot) firstDailySnapshot = dailyInvestorSnapshot;

    aggregateInvestorProfit += asNumber(dailyInvestorSnapshot.investorProfit);
    aggregateEligibleTotal += asNumber(dailyInvestorSnapshot.eligibleTotal);
    aggregateVfShare += asNumber(dailyInvestorSnapshot.vfShare);
    aggregateInstaShare += asNumber(dailyInvestorSnapshot.instaShare);
    aggregateVfProfit += asNumber(dailyInvestorSnapshot.vfProfit);
    aggregateInstaProfit += asNumber(dailyInvestorSnapshot.instaProfit);
    aggregateGrossProfit += asNumber(dailyInvestorSnapshot.totalGrossProfit);
    aggregateVfDailyFlow += asNumber(dailyInvestorSnapshot.vfDailyFlow);
    aggregateInstaDailyFlow += asNumber(dailyInvestorSnapshot.instaDailyFlow);
    aggregateTotalDailyFlow += asNumber(dailyInvestorSnapshot.totalDailyFlow);
    aggregateVfRawFlow += asNumber(dailyInvestorSnapshot.vfRawFlow);
    aggregateInstaRawFlow += asNumber(dailyInvestorSnapshot.instaRawFlow);
    aggregateInstaPayProfit += asNumber(dailyInvestorSnapshot.totalInstaPayProfit);
    aggregateInstaPayVolume += asNumber(dailyInvestorSnapshot.totalInstaPayVolume);
    aggregateCapitalShortfall += asNumber(dailyInvestorSnapshot.capitalShortfall);
    aggregateBuyEntries += asNumber(dailyInvestorSnapshot.buyEntriesCount);
    aggregateSellEntries += asNumber(dailyInvestorSnapshot.sellEntriesCount);
    aggregateAvgBuyWeighted += asNumber(dailyInvestorSnapshot.avgBuyPrice);
    aggregateAvgSellWeighted += asNumber(dailyInvestorSnapshot.avgSellPrice);
    aggregateVfProfitPer1000Weighted += asNumber(dailyInvestorSnapshot.vfProfitPer1000);
    aggregateInstaProfitPer1000Weighted += asNumber(dailyInvestorSnapshot.instaProfitPer1000);
  }

  await db.ref().update(updates);

  const divisor = Math.max(1, dateKeys.length);
  return {
    ...(firstDailySnapshot || {}),
    date: formatDateKey(date),
    workingDays: divisor,
    vfRawFlow: aggregateVfRawFlow,
    instaRawFlow: aggregateInstaRawFlow,
    vfDailyFlow: aggregateVfDailyFlow / divisor,
    instaDailyFlow: aggregateInstaDailyFlow / divisor,
    totalDailyFlow: aggregateTotalDailyFlow / divisor,
    capitalShortfall: aggregateCapitalShortfall / divisor,
    eligibleTotal: aggregateEligibleTotal,
    vfShare: aggregateVfShare,
    instaShare: aggregateInstaShare,
    avgBuyPrice: aggregateAvgBuyWeighted / divisor,
    avgSellPrice: aggregateAvgSellWeighted / divisor,
    buyEntriesCount: aggregateBuyEntries,
    sellEntriesCount: aggregateSellEntries,
    vfProfitPer1000: aggregateVfProfitPer1000Weighted / divisor,
    instaProfitPer1000: aggregateInstaProfitPer1000Weighted / divisor,
    totalInstaPayProfit: aggregateInstaPayProfit,
    totalInstaPayVolume: aggregateInstaPayVolume,
    vfProfit: aggregateVfProfit,
    instaProfit: aggregateInstaProfit,
    totalGrossProfit: aggregateGrossProfit,
    investorProfit: aggregateInvestorProfit,
    operationalProfit: distributionContext.operationalProfit,
    reconciledProfit: distributionContext.reconciledProfit,
    finalDistributableProfit: distributionContext.finalDistributableProfit,
    calculatedAt: Date.now()
  };
});

exports.payInvestorProfit = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') throw new HttpsError('permission-denied', 'Only admins can pay profit.');

  const { investorId, dates, bankAccountId, createdByUid } = request.data;
  if (!investorId || !dates || !Array.isArray(dates) || dates.length === 0 || !bankAccountId) {
    throw new HttpsError('invalid-argument', 'Invalid pay profit request.');
  }

  const db = admin.database();

  const allInvSnapsSnap = await db.ref(`investor_profit_snapshots/${investorId}`).once('value');
  const allInvSnaps = allInvSnapsSnap.exists() ? allInvSnapsSnap.val() : {};

  let totalPayout = 0;
  const snapshotsToUpdate = [];

  for (const date of dates) {
    const snap = allInvSnaps[date];
    if (snap && !snap.isPaid) {
      totalPayout += asNumber(snap.investorProfit);
      snapshotsToUpdate.push(date);
    }
  }

  if (snapshotsToUpdate.length === 0) {
    throw new HttpsError('failed-precondition', 'No unpaid snapshots found for the given dates.');
  }

  const bankRef = db.ref(`bank_accounts/${bankAccountId}`);
  const bankSnap = await bankRef.once('value');
  if (!bankSnap.exists()) throw new HttpsError('not-found', 'Bank account not found.');
  const bankName = bankSnap.val().bankName || 'Bank Account';

  const balanceResult = await bankRef.child('balance').transaction((current) => {
    if (current === null) return current;
    const balance = asNumber(current);
    if (balance < totalPayout) return;
    return balance - totalPayout;
  });

  if (!balanceResult.committed) {
    throw new HttpsError('failed-precondition', 'Insufficient bank balance.');
  }

  const investorSnap = await db.ref(`investors/${investorId}`).once('value');
  const investorName = investorSnap.exists() ? investorSnap.val().name : 'Investor';

  const nowTs = Date.now();
  const txId = uuidv4();
  const updates = {};

  for (const date of snapshotsToUpdate) {
    updates[`investor_profit_snapshots/${investorId}/${date}/isPaid`] = true;
    updates[`investor_profit_snapshots/${investorId}/${date}/paidAt`] = nowTs;
    updates[`investor_profit_snapshots/${investorId}/${date}/paidByUid`] = createdByUid || uid;
  }

  updates[`investors/${investorId}/totalProfitPaid`] = admin.database.ServerValue.increment(totalPayout);

  updates[`financial_ledger/${txId}`] = {
    id: txId,
    type: 'INVESTOR_PROFIT_PAID',
    amount: totalPayout,
    fromId: bankAccountId,
    fromLabel: bankName,
    toLabel: investorName,
    notes: `Profit for dates: ${dates.join(', ')}`,
    createdByUid: createdByUid || uid,
    timestamp: nowTs,
  };

  await db.ref().update(updates);
  return { success: true, totalPayout, datesCount: snapshotsToUpdate.length };
});

exports.withdrawInvestorCapital = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') throw new HttpsError('permission-denied', 'Only admins can withdraw capital.');

  const { investorId, amount, bankAccountId, createdByUid, notes } = request.data;
  const numAmount = asNumber(amount);
  if (!investorId || numAmount <= 0 || !bankAccountId) {
    throw new HttpsError('invalid-argument', 'Invalid withdrawal request.');
  }

  const db = admin.database();
  const investorSnap = await db.ref(`investors/${investorId}`).once('value');
  if (!investorSnap.exists()) throw new HttpsError('not-found', 'Investor not found.');
  const investor = investorSnap.val();

  if (numAmount > asNumber(investor.investedAmount)) {
    throw new HttpsError('invalid-argument', 'Withdrawal amount exceeds invested amount.');
  }

  const bankRef = db.ref(`bank_accounts/${bankAccountId}`);
  const bankSnap = await bankRef.once('value');
  if (!bankSnap.exists()) throw new HttpsError('not-found', 'Bank account not found.');
  const bankName = bankSnap.val().bankName || 'Bank Account';

  const balanceResult = await bankRef.child('balance').transaction((current) => {
    if (current === null) return current;
    const balance = asNumber(current);
    if (balance < numAmount) return;
    return balance - numAmount;
  });

  if (!balanceResult.committed) {
    throw new HttpsError('failed-precondition', 'Insufficient bank balance for withdrawal.');
  }

  const newInvestedAmount = asNumber(investor.investedAmount) - numAmount;
  const newHalfInvestedAmount = newInvestedAmount / 2;
  const newStatus = newInvestedAmount <= 0 ? 'withdrawn' : 'active';

  const nowTs = Date.now();
  const txId = uuidv4();
  const updates = {};

  updates[`investors/${investorId}/investedAmount`] = newInvestedAmount;
  updates[`investors/${investorId}/halfInvestedAmount`] = newHalfInvestedAmount;
  updates[`investors/${investorId}/status`] = newStatus;

  updates[`financial_ledger/${txId}`] = {
    id: txId,
    type: 'INVESTOR_CAPITAL_OUT',
    amount: numAmount,
    fromId: bankAccountId,
    fromLabel: bankName,
    toLabel: investor.name || 'Investor',
    notes: notes || 'Capital Withdrawal',
    createdByUid: createdByUid || uid,
    timestamp: nowTs,
  };

  await db.ref().update(updates);
  return { success: true, newInvestedAmount, newStatus };
});
