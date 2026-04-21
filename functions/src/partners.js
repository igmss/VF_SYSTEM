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
  _computeReconciledProfit,
} = require('./shared/profitEngine');

const REGION = 'asia-east1';

/**
 * NEW V4.0: Calculates cumulative profit for all partners.
 * Based on: (Assets + Loans) - (Opening Capital + Investor Capital).
 */
exports.getPartnerPerformance = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  
  const db = admin.database();
  const [
    configSnap,
    capitalHistorySnap,
    partnersSnap,
    investorsSnap,
    banksSnap,
    usdSnap,
    retailersSnap,
    collectorsSnap,
    loansSnap,
    moduleDatesSnap,
    mobileNumbersSnap
  ] = await Promise.all([
    db.ref('system_config/openingCapital').once('value'),
    db.ref('system_config/openingCapitalHistory').once('value'),
    db.ref('system_config/partners').once('value'),
    db.ref('investors').once('value'),
    db.ref('bank_accounts').once('value'),
    db.ref('usd_exchange').once('value'),
    db.ref('retailers').once('value'),
    db.ref('collectors').once('value'),
    db.ref('loans').once('value'),
    db.ref('system_config/module_start_dates').once('value'),
    db.ref('mobile_numbers').once('value')
  ]);

  const openingCapital = asNumber(configSnap.val());
  
  // Calculate Global Distributions (Everything paid out to date)
  let totalDistributionsSum = 0;
  if (partnersSnap.exists()) {
    partnersSnap.forEach(p => { totalDistributionsSum += asNumber(p.val().totalProfitPaid); });
  }
  if (investorsSnap.exists()) {
    investorsSnap.forEach(i => { totalDistributionsSum += asNumber(i.val().totalProfitPaid); });
  }

  const dbData = { openingCapital, ledgerSnap: null, banksSnap, usdSnap, retailersSnap, collectorsSnap, loansSnap, moduleDatesSnap, investorsSnap, mobileNumbersSnap };
  
  // 1. Calculate Business Health (Asset Growth + Distributions)
  const health = _computeReconciledProfit(dbData, totalDistributionsSum);
  const totalBusinessNetProfit = health.netProfit;

  // 2. Build daily flow map from ledger (same logic as V6.0 investor engine)
  const activeInvestors = [];
  investorsSnap.forEach(c => {
    if (c.val().status === 'active') activeInvestors.push({ ...c.val(), id: c.key });
  });
  activeInvestors.sort((a, b) => formatDateKey(a.investmentDate).localeCompare(formatDateKey(b.investmentDate)));

  // Capital history (time-sensitive)
  const rawCapHistory = capitalHistorySnap.val() || {};
  if (Object.keys(rawCapHistory).length === 0) rawCapHistory['2000-01-01'] = asNumber(configSnap.val());
  const capitalHistory = Object.entries(rawCapHistory)
    .map(([d, v]) => ({ date: d, value: asNumber(v) }))
    .sort((a, b) => a.date.localeCompare(b.date));
  const getCapitalOnDate = (date) => {
    let val = capitalHistory[0].value;
    for (const e of capitalHistory) { if (e.date <= date) val = e.value; else break; }
    return val;
  };

  // Loan timeline (time-sensitive)
  const loanEvents2 = [];
  if (loansSnap.exists()) {
    loansSnap.forEach(child => {
      const loan = child.val();
      const toDate = (ts) => { const d = new Date(asNumber(ts)); return `${d.getUTCFullYear()}-${String(d.getUTCMonth()+1).padStart(2,'0')}-${String(d.getUTCDate()).padStart(2,'0')}`; };
      loanEvents2.push({ principal: asNumber(loan.principalAmount), issuedDate: toDate(loan.issuedAt), repaidDate: loan.repaidAt ? toDate(loan.repaidAt) : null });
    });
  }
  const getLoansOnDate2 = (date) => {
    let out = 0;
    loanEvents2.forEach(({ principal, issuedDate, repaidDate }) => {
      if (issuedDate > date) return;
      if (repaidDate && repaidDate <= date) return;
      out += principal;
    });
    return out;
  };

  const ledgerSnap2 = await db.ref('financial_ledger').once('value');
  const dailyFlowMap = {};
  if (ledgerSnap2.exists()) {
    ledgerSnap2.forEach((child) => {
      const tx = child.val();
      if (tx.type !== 'DISTRIBUTE_VFCASH' && tx.type !== 'DISTRIBUTE_INSTAPAY') return;
      const dt = new Date(tx.timestamp);
      const dateKey = `${dt.getUTCFullYear()}-${String(dt.getUTCMonth()+1).padStart(2,'0')}-${String(dt.getUTCDate()).padStart(2,'0')}`;
      if (!dailyFlowMap[dateKey]) dailyFlowMap[dateKey] = { vf: 0, insta: 0 };
      if (tx.type === 'DISTRIBUTE_VFCASH')   dailyFlowMap[dateKey].vf    += asNumber(tx.amount);
      if (tx.type === 'DISTRIBUTE_INSTAPAY') dailyFlowMap[dateKey].insta += asNumber(tx.amount);
    });
  }

  // 3. Calculate TOTAL Investor Earnings using V6.1 formula (time-sensitive tiered capped hurdle)
  const getInvestorCapitalOnDate = (inv, date) => {
    if (!inv.capitalHistory) return asNumber(inv.investedAmount);
    const history = Object.entries(inv.capitalHistory)
      .map(([d, v]) => ({ date: d, value: asNumber(v) }))
      .sort((a, b) => a.date.localeCompare(b.date));
    if (history.length === 0) return asNumber(inv.investedAmount);
    let val = history[0].value;
    for (const entry of history) {
      if (entry.date <= date) val = entry.value;
      else break;
    }
    return val;
  };

  const getPrecedingHalfCapitalOnDate = (currentInvestorId, date) => {
    let sum = 0;
    for (const inv of activeInvestors) {
      if (inv.id === currentInvestorId) break;
      if (formatDateKey(inv.investmentDate) <= date) {
        sum += getInvestorCapitalOnDate(inv, date) / 2;
      }
    }
    return sum;
  };

  let totalInvestorEarningsAll = 0;
  activeInvestors.forEach((investor) => {
    const sharePercent = asNumber(investor.profitSharePercent);
    const startDate = formatDateKey(investor.investmentDate);
    Object.entries(dailyFlowMap)
      .filter(([date]) => date >= startDate)
      .forEach(([date, { vf, insta }]) => {
        const effectiveCap = getCapitalOnDate(date) - getLoansOnDate2(date);
        const baseHurdle = (effectiveCap / 2);
        const precedingHalfCap = getPrecedingHalfCapitalOnDate(investor.id, date);
        const investorHurdle = baseHurdle + precedingHalfCap;

        const totalFlow = vf + insta;
        const grossExcess = Math.max(0, totalFlow - investorHurdle);
        if (grossExcess <= 0) return;

        const myHistoricalCap = getInvestorCapitalOnDate(investor, date);
        const myHalfCap = myHistoricalCap / 2;
        const allowedExcess = Math.min(grossExcess, myHalfCap);

        if (allowedExcess <= 0) return;

        const ratio = totalFlow > 0 ? vf / totalFlow : 0;
        totalInvestorEarningsAll +=
          (allowedExcess * ratio     / 1000) * 7 * (sharePercent / 100) +
          (allowedExcess * (1-ratio) / 1000) * 5 * (sharePercent / 100);
      });
  });

  // 4. Calculate Partner Pool = Business Profit - Investor Earnings
  const partnerPool = Math.max(0, totalBusinessNetProfit - totalInvestorEarningsAll);
  const partnersBreakdown = {};

  if (partnersSnap.exists()) {
    partnersSnap.forEach((child) => {
      const p = child.val();
      if (p.status !== 'active' && p.status !== undefined) return;
      
      const share = partnerPool * (asNumber(p.sharePercent) / 100);
      partnersBreakdown[child.key] = {
        name: p.name,
        sharePercent: p.sharePercent,
        totalEarned: share,
        totalPaid: asNumber(p.totalProfitPaid),
        payableBalance: Math.max(0, share - asNumber(p.totalProfitPaid))
      };
    });
  }

  // 4. Summary for Dashboard
  let totalPayable = 0;
  Object.values(partnersBreakdown).forEach(p => {
    totalPayable += p.payableBalance;
  });

  return {
    success: true,
    businessNetProfit: totalBusinessNetProfit,
    totalInvestorProfitDeducted: totalInvestorEarningsAll,
    partnerPool,
    totalPayable,
    partnerBreakdown: partnersBreakdown,
    assetsSummary: health
  };
});

exports.payPartnerProfit = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') throw new HttpsError('permission-denied', 'Admin access required.');

  const { partnerId, amount, paymentSourceType, paymentSourceId, createdByUid, notes } = request.data;
  const numAmount = asNumber(amount);
  
  if (!partnerId || numAmount <= 0 || !paymentSourceType || !paymentSourceId) {
    throw new HttpsError('invalid-argument', 'Missing payment parameters.');
  }

  const db = admin.database();
  const partnerRef = db.ref(`system_config/partners/${partnerId}`);
  const partnerSnap = await partnerRef.once('value');

  if (!partnerSnap.exists()) throw new HttpsError('not-found', 'Partner not found.');
  const partner = partnerSnap.val();

  const nowTs = Date.now();
  const txId = uuidv4();
  const updates = {};

  if (paymentSourceType === 'bank') {
    const sourceRef = db.ref(`bank_accounts/${paymentSourceId}`);
    const sourceSnap = await sourceRef.once('value');
    if (!sourceSnap.exists()) throw new HttpsError('not-found', 'Bank account not found.');

    const balanceResult = await sourceRef.child('balance').transaction((current) => {
      if (current === null) return current;
      if (asNumber(current) < numAmount) return undefined;
      return asNumber(current) - numAmount;
    });

    if (!balanceResult.committed) throw new HttpsError('failed-precondition', 'Bank balance insufficient.');

    updates[`financial_ledger/${txId}`] = {
      id: txId,
      type: 'PARTNER_PROFIT_PAID_BANK',
      amount: numAmount,
      fromId: paymentSourceId,
      fromLabel: sourceSnap.val().bankName || 'Bank',
      toLabel: partner.name,
      notes: notes || `Partner profit payout (V4.0)`,
      createdByUid: createdByUid || uid,
      timestamp: nowTs,
    };
    updates[`bank_accounts/${paymentSourceId}/lastUpdatedAt`] = new Date(nowTs).toISOString();
  } else if (paymentSourceType === 'vf') {
    const sourceRef = db.ref(`mobile_numbers/${paymentSourceId}`);
    const sourceSnap = await sourceRef.once('value');
    if (!sourceSnap.exists()) throw new HttpsError('not-found', 'VF number not found.');

    updates[`mobile_numbers/${paymentSourceId}/outTotalUsed`] = admin.database.ServerValue.increment(numAmount);
    updates[`mobile_numbers/${paymentSourceId}/lastUpdatedAt`] = new Date(nowTs).toISOString();

    updates[`financial_ledger/${txId}`] = {
      id: txId,
      type: 'PARTNER_PROFIT_PAID_VF',
      amount: numAmount,
      fromId: paymentSourceId,
      fromLabel: sourceSnap.val().phoneNumber || 'VF Number',
      toLabel: partner.name,
      notes: notes || `Partner profit payout (V4.0)`,
      createdByUid: createdByUid || uid,
      timestamp: nowTs,
    };
  }

  updates[`system_config/partners/${partnerId}/totalProfitPaid`] = admin.database.ServerValue.increment(numAmount);
  updates[`system_config/partners/${partnerId}/lastPaidAt`] = nowTs;

  await db.ref().update(updates);
  return { success: true, amount: numAmount };
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
