const { HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const DB_URL = 'https://vodatracking-default-rtdb.firebaseio.com';

if (admin.apps.length === 0) {
  admin.initializeApp({ databaseURL: DB_URL });
}

function asNumber(value) {
  if (value == null) return 0;
  if (typeof value === 'number') return value;
  const parsed = parseFloat(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function getMobileNumberBalance(number) {
  return asNumber(number.initialBalance) + asNumber(number.inTotalUsed) - asNumber(number.outTotalUsed);
}

function getRetailerOutstandingDebt(retailer) {
  const outstanding = asNumber(retailer.totalAssigned) - asNumber(retailer.totalCollected);
  return outstanding > 0 ? outstanding : 0;
}

function getRetailerInstaPayOutstandingDebt(retailer) {
  const outstanding = asNumber(retailer.instaPayTotalAssigned) - asNumber(retailer.instaPayTotalCollected);
  return outstanding > 0 ? outstanding : 0;
}

function getTransactionTimestampMs(tx) {
  if (!tx) return Date.now();
  if (typeof tx.timestamp === 'number') return tx.timestamp;
  const parsed = Date.parse(tx.timestamp || '');
  return Number.isFinite(parsed) ? parsed : Date.now();
}

function safeDate(val, fallback) {
  const d = new Date(val);
  return isNaN(d.getTime()) ? new Date(fallback) : d;
}

function applyMobileNumberUsageDelta(updates, { numberId, amountDelta, direction, timestampMs, nowIso }) {
  if (!numberId || amountDelta === 0) return;

  const effectiveTs = Number.isFinite(timestampMs) ? timestampMs : Date.now();
  const prefix = direction === 'incoming' ? 'in' : 'out';
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime();

  updates[`mobile_numbers/${numberId}/${prefix}TotalUsed`] = admin.database.ServerValue.increment(amountDelta);
  if (effectiveTs >= todayStart) {
    updates[`mobile_numbers/${numberId}/${prefix}DailyUsed`] = admin.database.ServerValue.increment(amountDelta);
  }
  if (effectiveTs >= monthStart) {
    updates[`mobile_numbers/${numberId}/${prefix}MonthlyUsed`] = admin.database.ServerValue.increment(amountDelta);
  }
  updates[`mobile_numbers/${numberId}/lastUpdatedAt`] = nowIso || new Date().toISOString();
}

async function getGeneratedTransactions(prefix) {
  const snap = await admin.database().ref('transactions').orderByChild('bybitOrderId').equalTo(prefix).once('value');
  if (!snap.exists()) return [];
  return Object.entries(snap.val()).map(([key, value]) => ({ key, value }));
}

function buildGeneratedTransactionRemovals(generatedTransactions) {
  const removals = {};
  generatedTransactions.forEach(({ key }) => {
    removals[`transactions/${key}`] = null;
  });
  return removals;
}

async function getRelatedLedgerEntries(relatedLedgerId, allowedTypes = null) {
  const snap = await admin.database().ref('financial_ledger').orderByChild('relatedLedgerId').equalTo(relatedLedgerId).once('value');
  if (!snap.exists()) return [];

  return Object.entries(snap.val())
    .map(([key, value]) => ({ key, value }))
    .filter(({ value }) => {
      if (!allowedTypes || allowedTypes.length === 0) return true;
      return allowedTypes.includes(value?.type?.toString() || '');
    });
}

function buildLedgerRemovals(entries) {
  const removals = {};
  entries.forEach(({ key }) => {
    removals[`financial_ledger/${key}`] = null;
  });
  return removals;
}

function sumEntryAmounts(entries) {
  return entries.reduce((sum, { value }) => sum + asNumber(value?.amount), 0);
}

async function updateMobileNumberUsageTransaction({
  numberId,
  amountDelta,
  direction,
  timestampMs,
  nowIso,
  requireSufficientBalance = false,
  clampAtZero = false,
}) {
  const prefix = direction === 'incoming' ? 'in' : 'out';
  const effectiveTs = Number.isFinite(timestampMs) ? timestampMs : Date.now();
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime();
  const totalKey = `${prefix}TotalUsed`;
  const dailyKey = `${prefix}DailyUsed`;
  const monthlyKey = `${prefix}MonthlyUsed`;

  return await admin.database().ref(`mobile_numbers/${numberId}`).transaction((current) => {
    if (current === null) return current;

    if (requireSufficientBalance && direction === 'outgoing' && amountDelta > 0) {
      const currentBalance = getMobileNumberBalance(current);
      if ((amountDelta - currentBalance) > 0.01) {
        return; // Explicit abort: truly insufficient balance
      }
    }

    const nextTotal = asNumber(current[totalKey]) + amountDelta;
    if (!clampAtZero && amountDelta < 0 && nextTotal < -0.01) {
      return; // Explicit abort: would go negative
    }

    const next = {
      ...current,
      [totalKey]: clampAtZero ? Math.max(0, nextTotal) : nextTotal,
      lastUpdatedAt: nowIso || new Date().toISOString(),
    };

    if (effectiveTs >= todayStart) {
      const nextDaily = asNumber(current[dailyKey]) + amountDelta;
      if (!clampAtZero && amountDelta < 0 && nextDaily < -0.01) {
        return; // Explicit abort
      }
      next[dailyKey] = clampAtZero ? Math.max(0, nextDaily) : nextDaily;
    }

    if (effectiveTs >= monthStart) {
      const nextMonthly = asNumber(current[monthlyKey]) + amountDelta;
      if (!clampAtZero && amountDelta < 0 && nextMonthly < -0.01) {
        return; // Explicit abort
      }
      next[monthlyKey] = clampAtZero ? Math.max(0, nextMonthly) : nextMonthly;
    }

    return next;
  });
}

async function computeDistributionAmounts({ db, retailerId, amount, fees, chargeFeesToRetailer, applyCredit }) {
  const snap = await db.ref(`retailers/${retailerId}`).once('value');
  if (!snap.exists()) throw new HttpsError('not-found', 'Retailer not found.');
  const retailer = snap.val();

  const discountPer1000 = asNumber(retailer.discountPer1000);
  const discountAmount = (amount / 1000.0) * discountPer1000;
  const feeToCharge = chargeFeesToRetailer ? fees : 0.0;
  let actualDebtIncrease = Math.ceil(amount + discountAmount + feeToCharge);
  let creditUsed = 0.0;

  const currentCredit = asNumber(retailer.credit);
  if (applyCredit && currentCredit > 0) {
    creditUsed = Math.min(currentCredit, actualDebtIncrease);
    actualDebtIncrease -= creditUsed;
  }

  return { retailer, actualDebtIncrease, creditUsed };
}

async function getCallerRole(uid) {
  const snap = await admin.database().ref(`users/${uid}`).once('value');
  const user = snap.val();
  return user?.role || null;
}

async function requireFinanceRole(uid, allowCollector = false) {
  const role = await getCallerRole(uid);
  const allowed = allowCollector
    ? ['ADMIN', 'FINANCE', 'COLLECTOR']
    : ['ADMIN', 'FINANCE'];
  if (!role || !allowed.includes(role)) {
    throw new HttpsError('permission-denied', 'Unauthorized');
  }
  return role;
}

module.exports = {
  asNumber,
  getMobileNumberBalance,
  getRetailerOutstandingDebt,
  getRetailerInstaPayOutstandingDebt,
  getTransactionTimestampMs,
  safeDate,
  applyMobileNumberUsageDelta,
  getGeneratedTransactions,
  buildGeneratedTransactionRemovals,
  getRelatedLedgerEntries,
  buildLedgerRemovals,
  sumEntryAmounts,
  updateMobileNumberUsageTransaction,
  computeDistributionAmounts,
  getCallerRole,
  requireFinanceRole,
};
