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
  _calculateInvestorEarningsFixedRate,
  _computeReconciledProfit,
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
    capitalHistory: { [formatDateKey(investmentDate || nowTs)]: numAmount }
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

/**
 * V6.0: Time-sensitive hurdle system.
 * Each day's hurdle = (effectiveCapital(date) / 2) + precedingCapital
 * Where: effectiveCapital(date) = openingCapital that was set on or before that date
 *                               - outstanding loan principal on that date
 * Changing openingCapital or issuing/repaying loans ONLY affects calculations
 * from that event date forward — historical dates are never retroactively changed.
 */
exports.getInvestorPerformance = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');

  const { investorId } = request.data;
  const db = admin.database();

  const [capitalSnap, capitalHistorySnap, ledgerSnap, investorsSnap, loansSnap] = await Promise.all([
    db.ref('system_config/openingCapital').once('value'),
    db.ref('system_config/openingCapitalHistory').once('value'),
    db.ref('financial_ledger').once('value'),
    db.ref('investors').orderByChild('status').equalTo('active').once('value'),
    db.ref('loans').once('value'),
  ]);

  // ── Capital history: { 'YYYY-MM-DD': value } ───────────────────────────
  // Seed: if no history exists, treat the current value as valid from epoch
  const rawHistory = capitalHistorySnap.val() || {};
  if (Object.keys(rawHistory).length === 0) {
    rawHistory['2000-01-01'] = asNumber(capitalSnap.val()); // fallback for all dates
  }
  const capitalHistory = Object.entries(rawHistory)
    .map(([d, v]) => ({ date: d, value: asNumber(v) }))
    .sort((a, b) => a.date.localeCompare(b.date)); // ascending

  // Returns the openingCapital that was set on or before the given date
  const getCapitalOnDate = (date) => {
    let val = capitalHistory[0].value;
    for (const entry of capitalHistory) {
      if (entry.date <= date) val = entry.value;
      else break;
    }
    return val;
  };

  // ── Loan timeline: list of { issuedDate, principal, repaidDate|null } ──
  const loanEvents = [];
  if (loansSnap.exists()) {
    loansSnap.forEach((child) => {
      const loan = child.val();
      const issuedDate = (() => {
        const d = new Date(asNumber(loan.issuedAt));
        return `${d.getUTCFullYear()}-${String(d.getUTCMonth()+1).padStart(2,'0')}-${String(d.getUTCDate()).padStart(2,'0')}`;
      })();
      const repaidDate = loan.repaidAt ? (() => {
        const d = new Date(asNumber(loan.repaidAt));
        return `${d.getUTCFullYear()}-${String(d.getUTCMonth()+1).padStart(2,'0')}-${String(d.getUTCDate()).padStart(2,'0')}`;
      })() : null;
      loanEvents.push({
        principal: asNumber(loan.principalAmount),
        issuedDate,
        repaidDate, // null = still outstanding
      });
    });
  }

  // Returns total outstanding loan principal on a specific date
  const getLoansOnDate = (date) => {
    let outstanding = 0;
    loanEvents.forEach(({ principal, issuedDate, repaidDate }) => {
      if (issuedDate > date) return; // not yet issued
      if (repaidDate && repaidDate <= date) return; // already fully repaid
      outstanding += principal;
    });
    return outstanding;
  };

  // ── Step 1: Build daily flow map from ledger ───────────────────────────
  const dailyFlow = {};
  if (ledgerSnap.exists()) {
    ledgerSnap.forEach((child) => {
      const tx = child.val();
      if (tx.type !== 'DISTRIBUTE_VFCASH' && tx.type !== 'DISTRIBUTE_INSTAPAY') return;
      const dt = new Date(asNumber(tx.timestamp));
      const dateKey = `${dt.getUTCFullYear()}-${String(dt.getUTCMonth()+1).padStart(2,'0')}-${String(dt.getUTCDate()).padStart(2,'0')}`;
      if (!dailyFlow[dateKey]) dailyFlow[dateKey] = { vf: 0, insta: 0 };
      if (tx.type === 'DISTRIBUTE_VFCASH')   dailyFlow[dateKey].vf    += asNumber(tx.amount);
      if (tx.type === 'DISTRIBUTE_INSTAPAY') dailyFlow[dateKey].insta += asNumber(tx.amount);
    });
  }

  // ── Step 2: Load investors ─────────────────────────────────────────────
  const activeInvestors = [];
  investorsSnap.forEach(c => activeInvestors.push({ ...c.val(), id: c.key }));
  activeInvestors.sort((a, b) =>
    formatDateKey(a.investmentDate).localeCompare(formatDateKey(b.investmentDate))
  );

  // ── Step 3: Core per-day profit calculator (time-sensitive tiered hurdle) ──
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

  const calcDay = (investor, date, vfFlow, instaFlow) => {
    const sharePercent = asNumber(investor.profitSharePercent);
    const effectiveCap = getCapitalOnDate(date) - getLoansOnDate(date);
    const baseHurdle = (effectiveCap / 2);
    const precedingHalfCap = getPrecedingHalfCapitalOnDate(investor.id, date);
    const investorHurdle = baseHurdle + precedingHalfCap;
    
    const totalFlow = vfFlow + instaFlow;
    const grossExcess = Math.max(0, totalFlow - investorHurdle);

    if (grossExcess <= 0) {
      return { hurdle: investorHurdle, effectiveCap, excessFlow: 0, vfExcess: 0, instaExcess: 0, vfProfit: 0, instaProfit: 0, profit: 0 };
    }

    const myHistoricalCap = getInvestorCapitalOnDate(investor, date);
    const myHalfCap = myHistoricalCap / 2;
    const allowedExcess = Math.min(grossExcess, myHalfCap);

    if (allowedExcess <= 0) {
      return { hurdle: investorHurdle, effectiveCap, excessFlow: 0, vfExcess: 0, instaExcess: 0, vfProfit: 0, instaProfit: 0, profit: 0 };
    }

    const ratio = totalFlow > 0 ? vfFlow / totalFlow : 0;
    const vfExcess    = allowedExcess * ratio;
    const instaExcess = allowedExcess * (1 - ratio);
    const vfProfit    = (vfExcess    / 1000) * 7 * (sharePercent / 100);
    const instaProfit = (instaExcess / 1000) * 5 * (sharePercent / 100);

    return { hurdle: investorHurdle, effectiveCap, excessFlow: allowedExcess, vfExcess, instaExcess, vfProfit, instaProfit, profit: vfProfit + instaProfit };
  };

  // ── Step 4: Return single or global ────────────────────────────────────
  if (investorId) {
    const investor = activeInvestors.find(i => i.id === investorId);
    if (!investor) throw new HttpsError('not-found', 'Investor not found or inactive.');

    const startDate = formatDateKey(investor.investmentDate);
    let totalEarned = 0;
    const dailyBreakdown = [];

    Object.keys(dailyFlow)
      .filter(d => d >= startDate)
      .sort((a, b) => b.localeCompare(a)) // newest first
      .forEach(date => {
        const { vf, insta } = dailyFlow[date];
        const d = calcDay(investor, date, vf, insta);
        totalEarned += d.profit;
        dailyBreakdown.push({
          date,
          vfFlow: vf,
          instaFlow: insta,
          effectiveCap: d.effectiveCap,
          hurdle: d.hurdle,
          excessFlow: d.excessFlow,
          vfExcess: d.vfExcess,
          instaExcess: d.instaExcess,
          vfProfit: d.vfProfit,
          instaProfit: d.instaProfit,
          profit: d.profit,
        });
      });

    const totalPaid = asNumber(investor.totalProfitPaid);
    return {
      success: true,
      investorId,
      totalEarned,
      totalPaid,
      totalVfFlow:    dailyBreakdown.reduce((s, d) => s + d.vfExcess, 0),
      totalInstaFlow: dailyBreakdown.reduce((s, d) => s + d.instaExcess, 0),
      payableBalance: Math.max(0, totalEarned - totalPaid),
      dailyBreakdown,
    };

  } else {
    // Global summary
    let globalTotalEarned  = 0;
    let globalTotalPaid    = 0;
    let globalTotalPayable = 0;
    const investorBreakdown = {};

    activeInvestors.forEach(investor => {
      const startDate = formatDateKey(investor.investmentDate);
      let totalEarned = 0;

      Object.entries(dailyFlow)
        .filter(([d]) => d >= startDate)
        .forEach(([date, { vf, insta }]) => {
          totalEarned += calcDay(investor, date, vf, insta).profit;
        });

      const paid    = asNumber(investor.totalProfitPaid);
      const payable = Math.max(0, totalEarned - paid);
      investorBreakdown[investor.id] = { name: investor.name, totalEarned, totalPaid: paid, payableBalance: payable };
      globalTotalEarned  += totalEarned;
      globalTotalPaid    += paid;
      globalTotalPayable += payable;
    });

    return { success: true, global: true, totalEarned: globalTotalEarned, totalPaid: globalTotalPaid, totalPayable: globalTotalPayable, investorBreakdown };
  }
});
exports.payInvestorProfit = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') throw new HttpsError('permission-denied', 'Only admins can pay profit.');

  const { investorId, amount, bankAccountId, notes, createdByUid } = request.data;
  const numAmount = asNumber(amount);
  if (!investorId || numAmount <= 0 || !bankAccountId) {
    throw new HttpsError('invalid-argument', 'Invalid pay profit request.');
  }

  const db = admin.database();
  const bankRef = db.ref(`bank_accounts/${bankAccountId}`);
  const bankSnap = await bankRef.once('value');
  if (!bankSnap.exists()) throw new HttpsError('not-found', 'Bank account not found.');
  const bankName = bankSnap.val().bankName || 'Bank Account';

  const balanceResult = await bankRef.child('balance').transaction((current) => {
    if (current === null) return current;
    const balance = asNumber(current);
    if (balance < numAmount) return; // Abort if insufficient funds
    return balance - numAmount;
  });

  if (!balanceResult.committed) {
    throw new HttpsError('failed-precondition', 'Insufficient bank balance.');
  }

  const investorRef = db.ref(`investors/${investorId}`);
  const investorSnap = await investorRef.once('value');
  const investor = investorSnap.val();

  const nowTs = Date.now();
  const txId = uuidv4();
  const updates = {};

  updates[`investors/${investorId}/totalProfitPaid`] = admin.database.ServerValue.increment(numAmount);
  updates[`investors/${investorId}/lastPaidAt`] = nowTs;

  updates[`financial_ledger/${txId}`] = {
    id: txId,
    type: 'INVESTOR_PROFIT_PAID',
    amount: numAmount,
    fromId: bankAccountId,
    fromLabel: bankName,
    toLabel: investor.name || 'Investor',
    notes: notes || 'Investor Profit Payout (V4.0)',
    createdByUid: createdByUid || uid,
    timestamp: nowTs,
  };

  await db.ref().update(updates);
  return { success: true, amount: numAmount };
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
  const dateKey = formatDateKey(nowTs);
  const txId = uuidv4();
  const updates = {};

  updates[`investors/${investorId}/investedAmount`] = newInvestedAmount;
  updates[`investors/${investorId}/halfInvestedAmount`] = newHalfInvestedAmount;
  updates[`investors/${investorId}/status`] = newStatus;
  updates[`investors/${investorId}/capitalHistory/${dateKey}`] = newInvestedAmount;

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
