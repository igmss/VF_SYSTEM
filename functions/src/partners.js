const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { v4: uuidv4 } = require('uuid');
const { asNumber, getCallerRole } = require('./shared/helpers');
const {
  PROFIT_CALCULATION_VERSION,
  formatDateKey,
  getDateKeysForRange,
  isInvestorEligibleForDate,
  _buildSystemProfitSnapshotForDate,
  _buildProfitDistributionContext,
  _buildInvestorSnapshotForDate,
  _buildPartnerSnapshotForDate,
} = require('./shared/profitEngine');

const REGION = 'asia-east1';

exports.calculatePartnerDailyProfit = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (!['ADMIN', 'FINANCE'].includes(role)) throw new HttpsError('permission-denied', 'Unauthorized');

  const { date, workingDays } = request.data;
  const numWorkingDays = asNumber(workingDays);
  if (numWorkingDays <= 0) throw new HttpsError('invalid-argument', 'workingDays must be > 0.');

  const db = admin.database();

  const [
    configSnap,
    partnersSnap,
    investorsSnap,
    ledgerSnap,
    banksSnap,
    usdSnap,
    retailersSnap,
    collectorsSnap,
    loansSnap,
    moduleDatesSnap,
    mobileNumbersSnap
  ] = await Promise.all([
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

  if (!configSnap.exists()) {
    throw new HttpsError('failed-precondition', 'system_config/openingCapital is not set.');
  }
  const openingCapital = asNumber(configSnap.val());

  const dbData = { openingCapital, ledgerSnap, banksSnap, usdSnap, retailersSnap, collectorsSnap, loansSnap, moduleDatesSnap, investorsSnap, mobileNumbersSnap };
  const dateKeys = getDateKeysForRange(date, numWorkingDays);

  // Build ALL system snapshots in memory first — no intermediate DB writes
  const systemSnapshots = {};
  const allUpdates = {};
  dateKeys.forEach((dayKey) => {
    systemSnapshots[dayKey] = _buildSystemProfitSnapshotForDate(dbData, dayKey);
    allUpdates[`system_profit_snapshots/${dayKey}`] = systemSnapshots[dayKey];
  });

  // Distribution context uses the freshly-built in-memory snapshots
  const distributionContext = _buildProfitDistributionContext(dateKeys, systemSnapshots, dbData);

  // Read existing snapshots once to check which are already paid (must be preserved)
  const [existingInvestorSnapshotsSnap, existingPartnerSnapshotsSnap] = await Promise.all([
    db.ref('investor_profit_snapshots').once('value'),
    db.ref('partner_profit_snapshots').once('value'),
  ]);
  const existingInvestorSnapshots = existingInvestorSnapshotsSnap.exists() ? existingInvestorSnapshotsSnap.val() : {};
  const existingPartnerSnapshots = existingPartnerSnapshotsSnap.exists() ? existingPartnerSnapshotsSnap.val() : {};

  // Build investor snapshots (paid ones are returned unchanged by _buildInvestorSnapshotForDate)
  const investorProfitByDate = {};
  dateKeys.forEach(k => { investorProfitByDate[k] = 0; });

  if (investorsSnap.exists()) {
    investorsSnap.forEach((child) => {
      const investorId = child.key;
      const investor = child.val();
      dateKeys.forEach((dayKey) => {
        if (!isInvestorEligibleForDate(investor, dayKey)) return;
        const existingInvSnap = existingInvestorSnapshots[investorId]?.[dayKey] || null;
        const rebuiltSnapshot = _buildInvestorSnapshotForDate(
          investor,
          systemSnapshots[dayKey],
          distributionContext.distributableProfitByDate[dayKey] || 0,
          existingInvSnap
        );
        allUpdates[`investor_profit_snapshots/${investorId}/${dayKey}`] = rebuiltSnapshot;
        investorProfitByDate[dayKey] += asNumber(rebuiltSnapshot.investorProfit);
      });
    });
  }

  let totalInvestorProfitDeducted = 0;
  dateKeys.forEach(k => { totalInvestorProfitDeducted += asNumber(investorProfitByDate[k]); });

  let overallBusinessNetProfitBeforeInvestors = 0;
  dateKeys.forEach((dayKey) => {
    overallBusinessNetProfitBeforeInvestors += asNumber(distributionContext.distributableProfitByDate[dayKey]);
  });
  const overallBusinessNetProfitAfterInvestors = Math.max(
    0,
    overallBusinessNetProfitBeforeInvestors - totalInvestorProfitDeducted
  );

  const partnersBreakdown = {};

  if (partnersSnap.exists()) {
    partnersSnap.forEach((child) => {
      const partnerId = child.key;
      const p = child.val();
      if (p.status !== 'active' && p.status !== undefined) return;

      let businessGrossProfit = 0;
      let businessNetProfitBeforeInvestors = 0;
      let totalVfFlowAgg = 0;
      let totalInstaFlowAgg = 0;
      let totalAvgBuy = 0;
      let totalAvgSell = 0;
      let totalInstaProfitPer1000 = 0;
      let totalVfProfitPer1000 = 0;
      let finalNetAfterInvestors = 0;
      let partnerProfitTotal = 0;

      dateKeys.forEach((dayKey) => {
        const daySnapshot = systemSnapshots[dayKey];
        const dayDistributableProfit = asNumber(distributionContext.distributableProfitByDate[dayKey] || 0);
        const dailyInvestorDeduction = asNumber(investorProfitByDate[dayKey] || 0);
        const existingPartnerSnapshot = existingPartnerSnapshots[partnerId]?.[dayKey] || null;
        const partnerDaySnapshot = _buildPartnerSnapshotForDate(
          p,
          daySnapshot,
          dayDistributableProfit,
          dailyInvestorDeduction,
          existingPartnerSnapshot
        );

        allUpdates[`partner_profit_snapshots/${partnerId}/${dayKey}`] = partnerDaySnapshot;
        partnerProfitTotal += asNumber(partnerDaySnapshot.partnerProfit);

        businessGrossProfit += asNumber(daySnapshot.businessGrossProfit);
        businessNetProfitBeforeInvestors += dayDistributableProfit;
        totalVfFlowAgg += asNumber(daySnapshot.vfDailyFlow);
        totalInstaFlowAgg += asNumber(daySnapshot.instaDailyFlow);
        totalAvgBuy += asNumber(daySnapshot.avgBuy);
        totalAvgSell += asNumber(daySnapshot.avgSell);
        totalInstaProfitPer1000 += asNumber(daySnapshot.systemInstaProfitPer1000);
        totalVfProfitPer1000 += asNumber(daySnapshot.spread);
        finalNetAfterInvestors += asNumber(partnerDaySnapshot.businessNetProfitAfterInvestors);
      });

      partnersBreakdown[partnerId] = {
        calculationVersion: PROFIT_CALCULATION_VERSION,
        date: formatDateKey(date),
        workingDays: numWorkingDays,
        systemAvgBuyPrice: totalAvgBuy / Math.max(1, numWorkingDays),
        systemAvgSellPrice: totalAvgSell / Math.max(1, numWorkingDays),
        systemInstaProfitPer1000: totalInstaProfitPer1000 / Math.max(1, numWorkingDays),
        businessGrossProfit,
        totalInvestorProfitDeducted,
        businessNetProfit: finalNetAfterInvestors,
        businessNetProfitBeforeInvestors,
        businessNetProfitAfterInvestors: finalNetAfterInvestors,
        sharePercent: asNumber(p.sharePercent),
        partnerProfit: partnerProfitTotal,
        vfDailyFlow: totalVfFlowAgg / Math.max(1, numWorkingDays),
        instaDailyFlow: totalInstaFlowAgg / Math.max(1, numWorkingDays),
        systemVfProfitPer1000: totalVfProfitPer1000 / Math.max(1, numWorkingDays),
        isPaid: false,
        calculatedAt: Date.now()
      };
    });
  }

  // Single atomic write — all system/investor/partner snapshots go out together
  if (Object.keys(allUpdates).length > 0) {
    await db.ref().update(allUpdates);
  }

  return {
    success: true,
    partnersBreakdown,
    businessNetProfitBeforeInvestors: overallBusinessNetProfitBeforeInvestors,
    businessNetProfitAfterInvestors: overallBusinessNetProfitAfterInvestors,
    operationalProfit: distributionContext.operationalProfit,
    reconciledProfit: distributionContext.reconciledProfit,
    finalDistributableProfit: distributionContext.finalDistributableProfit,
    totalInvestorProfitDeducted,
    workingDays: numWorkingDays
  };
});

exports.payPartnerProfit = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') throw new HttpsError('permission-denied', 'Admin access required.');

  const { partnerId, dates, paymentSourceType, paymentSourceId, createdByUid } = request.data;
  if (!partnerId || !dates || !Array.isArray(dates) || dates.length === 0 || !paymentSourceType || !paymentSourceId) {
    throw new HttpsError('invalid-argument', 'Missing payment parameters.');
  }

  const db = admin.database();
  const partnerRef = db.ref(`system_config/partners/${partnerId}`);
  const [partnerSnap, snapshotsSnap] = await Promise.all([
    partnerRef.once('value'),
    db.ref(`partner_profit_snapshots/${partnerId}`).once('value'),
  ]);

  if (!partnerSnap.exists()) throw new HttpsError('not-found', 'Partner not found.');
  const partner = partnerSnap.val();

  let totalPayout = 0;
  const unpaidSnapsToUpdate = [];

  const snaps = snapshotsSnap.val() || {};
  for (const date of dates) {
    const snap = snaps[date];
    if (snap && !snap.isPaid) {
      totalPayout += asNumber(snap.partnerProfit);
      unpaidSnapsToUpdate.push(date);
    }
  }

  if (unpaidSnapsToUpdate.length === 0) {
    throw new HttpsError('failed-precondition', 'No unpaid snapshots found for selected dates.');
  }

  const nowTs = Date.now();
  const txId = uuidv4();
  const updates = {};

  if (paymentSourceType === 'bank') {
    const sourceRef = db.ref(`bank_accounts/${paymentSourceId}`);
    const sourceSnap = await sourceRef.once('value');
    if (!sourceSnap.exists()) throw new HttpsError('not-found', 'Bank account not found.');

    const balanceResult = await sourceRef.child('balance').transaction((current) => {
      if (current === null) return current;
      if (asNumber(current) < totalPayout) return undefined;
      return asNumber(current) - totalPayout;
    });

    if (!balanceResult.committed) {
      throw new HttpsError('failed-precondition', 'Bank balance insufficient.');
    }

    updates[`financial_ledger/${txId}`] = {
      id: txId,
      type: 'PARTNER_PROFIT_PAID_BANK',
      amount: totalPayout,
      fromId: paymentSourceId,
      fromLabel: sourceSnap.val().bankName || 'Bank',
      toLabel: partner.name,
      notes: `Partner profit paid for ${unpaidSnapsToUpdate.length} days`,
      createdByUid: createdByUid || uid,
      timestamp: nowTs,
    };
    updates[`bank_accounts/${paymentSourceId}/lastUpdatedAt`] = new Date(nowTs).toISOString();
  } else if (paymentSourceType === 'vf') {
    const sourceRef = db.ref(`mobile_numbers/${paymentSourceId}`);
    const sourceSnap = await sourceRef.once('value');
    if (!sourceSnap.exists()) throw new HttpsError('not-found', 'VF number not found.');

    const inTotalUsed = asNumber(sourceSnap.val().inTotalUsed);
    const outTotalUsed = asNumber(sourceSnap.val().outTotalUsed);
    if ((inTotalUsed - outTotalUsed) < totalPayout) {
      throw new HttpsError('failed-precondition', 'VF number balance insufficient.');
    }

    updates[`mobile_numbers/${paymentSourceId}/outTotalUsed`] = admin.database.ServerValue.increment(totalPayout);
    updates[`mobile_numbers/${paymentSourceId}/outDailyUsed`] = admin.database.ServerValue.increment(totalPayout);
    updates[`mobile_numbers/${paymentSourceId}/outMonthlyUsed`] = admin.database.ServerValue.increment(totalPayout);
    updates[`mobile_numbers/${paymentSourceId}/lastUpdatedAt`] = new Date(nowTs).toISOString();

    updates[`financial_ledger/${txId}`] = {
      id: txId,
      type: 'PARTNER_PROFIT_PAID_VF',
      amount: totalPayout,
      fromId: paymentSourceId,
      fromLabel: sourceSnap.val().phoneNumber || 'VF Number',
      toLabel: partner.name,
      notes: `Partner profit paid for ${unpaidSnapsToUpdate.length} days`,
      createdByUid: createdByUid || uid,
      timestamp: nowTs,
    };
  } else {
    throw new HttpsError('invalid-argument', 'Invalid payment source type.');
  }

  unpaidSnapsToUpdate.forEach(date => {
    updates[`partner_profit_snapshots/${partnerId}/${date}/isPaid`] = true;
    updates[`partner_profit_snapshots/${partnerId}/${date}/paidAt`] = nowTs;
    updates[`partner_profit_snapshots/${partnerId}/${date}/paidByUid`] = createdByUid || uid;
    updates[`partner_profit_snapshots/${partnerId}/${date}/paidFromType`] = paymentSourceType;
    updates[`partner_profit_snapshots/${partnerId}/${date}/paidFromId`] = paymentSourceId;
  });

  updates[`system_config/partners/${partnerId}/totalProfitPaid`] = admin.database.ServerValue.increment(totalPayout);

  await db.ref().update(updates);

  return { success: true, totalPayout, datesCount: unpaidSnapsToUpdate.length };
});

exports.seedPartners = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') throw new HttpsError('permission-denied', 'Admin access required.');

  const db = admin.database();
  const partnersSnap = await db.ref('system_config/partners').once('value');

  if (partnersSnap.exists() && Object.keys(partnersSnap.val() || {}).length > 0) {
    return { alreadySeeded: true };
  }

  const partners = [
    { id: uuidv4(), name: 'Mostafa Abbas', sharePercent: 40, status: 'active' },
    { id: uuidv4(), name: 'Ibrahim', sharePercent: 35, status: 'active' },
    { id: uuidv4(), name: 'Mostafa Galhom', sharePercent: 25, status: 'active' },
  ];

  const updates = {};
  const now = Date.now();
  partners.forEach(p => {
    updates[`system_config/partners/${p.id}`] = {
      ...p,
      totalProfitPaid: 0,
      createdAt: now
    };
  });

  await db.ref().update(updates);
  return { success: true, seeded: true };
});

exports.savePartner = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') throw new HttpsError('permission-denied', 'Admin access required.');

  const { partner } = request.data;
  if (!partner || !partner.name) throw new HttpsError('invalid-argument', 'Partner name is required.');
  const newShare = asNumber(partner.sharePercent);
  if (newShare <= 0 || newShare > 100) throw new HttpsError('invalid-argument', 'Share percent must be between 0 and 100.');

  const db = admin.database();
  const partnerId = partner.id || uuidv4();

  const existingPartnersSnap = await db.ref('system_config/partners').once('value');
  let otherShareTotal = 0;
  if (existingPartnersSnap.exists()) {
    existingPartnersSnap.forEach((child) => {
      const p = child.val();
      if (child.key === partnerId) return;
      if (p.status === 'inactive') return;
      otherShareTotal += asNumber(p.sharePercent);
    });
  }
  if (otherShareTotal + newShare > 100) {
    throw new HttpsError(
      'invalid-argument',
      `Total share would be ${otherShareTotal + newShare}%. Cannot exceed 100%. Other active partners use ${otherShareTotal}%.`
    );
  }

  const partnerData = {
    ...partner,
    id: partnerId,
    status: partner.status || 'active',
    updatedAt: Date.now(),
    createdAt: partner.createdAt || Date.now(),
    totalProfitPaid: asNumber(partner.totalProfitPaid)
  };

  await db.ref(`system_config/partners/${partnerId}`).set(partnerData);
  return { success: true, partnerId };
});

exports.setPartnerStatus = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') throw new HttpsError('permission-denied', 'Admin access required.');

  const { partnerId, status } = request.data;
  if (!partnerId || !status) throw new HttpsError('invalid-argument', 'Partner ID and status are required.');

  await admin.database().ref(`system_config/partners/${partnerId}/status`).set(status);
  return { success: true };
});
