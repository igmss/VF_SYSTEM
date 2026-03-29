const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { v4: uuidv4 } = require('uuid');
const REGION = 'asia-east1';

if (admin.apps.length === 0) {
  admin.initializeApp();
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

function getTransactionTimestampMs(tx) {
  if (!tx) return Date.now();
  if (typeof tx.timestamp === 'number') return tx.timestamp;
  const parsed = Date.parse(tx.timestamp || '');
  return Number.isFinite(parsed) ? parsed : Date.now();
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

/**
 * Reads retailer data and computes distribution amounts.
 * The actual balance update is applied later via an atomic multi-path write.
 */
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

exports.setBybitCredentials = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') {
    throw new HttpsError('permission-denied', 'Only admins can manage credentials.');
  }

  const apiKey = request.data?.apiKey?.toString().trim();
  const apiSecret = request.data?.apiSecret?.toString().trim();
  if (!apiKey || !apiSecret) {
    throw new HttpsError('invalid-argument', 'API credentials are required.');
  }

  const nowIso = new Date().toISOString();
  await admin.database().ref().update({
    'system/api_credentials/bybit/apiKey': apiKey,
    'system/api_credentials/bybit/apiSecret': apiSecret,
    'system/api_credentials/bybit/updatedAt': nowIso,
    'system/api_credentials/bybit_metadata/configured': true,
    'system/api_credentials/bybit_metadata/updatedAt': nowIso,
  });

  return { configured: true, updatedAt: nowIso };
});

exports.clearBybitCredentials = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') {
    throw new HttpsError('permission-denied', 'Only admins can manage credentials.');
  }

  const nowIso = new Date().toISOString();
  await admin.database().ref().update({
    'system/api_credentials/bybit': null,
    'system/api_credentials/bybit_metadata/configured': false,
    'system/api_credentials/bybit_metadata/updatedAt': nowIso,
  });

  return { configured: false, updatedAt: nowIso };
});

exports.setCollectorVfDepositFeePer1000 = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const feePer1000 = asNumber(request.data?.feePer1000);
  if (feePer1000 < 0) {
    throw new HttpsError('invalid-argument', 'Fee per 1000 must be zero or greater.');
  }

  const nowIso = new Date().toISOString();
  await admin.database().ref().update({
    'system/operation_settings/collectorVfDepositFeePer1000': feePer1000,
    'system/operation_settings/updatedAt': nowIso,
  });

  return { feePer1000, updatedAt: nowIso };
});

exports.fundBankAccount = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const bankAccountId = request.data?.bankAccountId?.toString();
  const amount = asNumber(request.data?.amount);
  const createdByUid = uid;
  const notes = request.data?.notes?.toString().trim() || null;
  if (!bankAccountId || amount <= 0) {
    throw new HttpsError('invalid-argument', 'Invalid fund request.');
  }

  const bankSnap = await admin.database().ref(`bank_accounts/${bankAccountId}`).once('value');
  if (!bankSnap.exists()) throw new HttpsError('not-found', 'Bank account not found.');
  const bank = bankSnap.val();
  const txId = uuidv4();
  const nowIso = new Date().toISOString();

  await admin.database().ref().update({
    [`financial_ledger/${txId}`]: {
      id: txId,
      type: 'FUND_BANK',
      amount,
      toId: bankAccountId,
      toLabel: bank.bankName || 'Bank Account',
      createdByUid,
      notes,
      timestamp: Date.now(),
    },
    [`bank_accounts/${bankAccountId}/balance`]: admin.database.ServerValue.increment(amount),
    [`bank_accounts/${bankAccountId}/lastUpdatedAt`]: nowIso,
  });

  return { txId };
});

exports.deductBankBalance = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const bankAccountId = request.data?.bankAccountId?.toString();
  const amount = asNumber(request.data?.amount);
  const createdByUid = uid;
  const notes = request.data?.notes?.toString().trim() || null;
  if (!bankAccountId || amount <= 0) {
    throw new HttpsError('invalid-argument', 'Invalid deduction request.');
  }

  const bankRef = admin.database().ref(`bank_accounts/${bankAccountId}`);
  const bankSnap = await bankRef.once('value');
  if (!bankSnap.exists()) throw new HttpsError('not-found', 'Bank account not found.');
  const bank = bankSnap.val();
  const balanceResult = await bankRef.child('balance').transaction((current) => {
    const next = asNumber(current) - amount;
    if (next < 0) return;
    return next;
  });
  if (!balanceResult.committed) {
    throw new HttpsError('failed-precondition', 'Bank balance cannot go negative.');
  }

  const txId = uuidv4();
  const nowIso = new Date().toISOString();
  try {
    await admin.database().ref().update({
      [`financial_ledger/${txId}`]: {
        id: txId,
        type: 'BANK_DEDUCTION',
        amount,
        fromId: bankAccountId,
        fromLabel: bank.bankName || 'Bank Account',
        createdByUid,
        notes,
        timestamp: Date.now(),
      },
      [`bank_accounts/${bankAccountId}/lastUpdatedAt`]: nowIso,
    });
  } catch (error) {
    await bankRef.child('balance').transaction((current) => asNumber(current) + amount);
    throw new HttpsError('internal', error.message || 'Unable to complete deduction.');
  }

  return { txId };
});

exports.correctBankBalance = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const bankAccountId = request.data?.bankAccountId?.toString();
  const newBalance = asNumber(request.data?.newBalance);
  const createdByUid = uid;
  const notes = request.data?.notes?.toString().trim() || null;
  if (!bankAccountId || newBalance < 0) {
    throw new HttpsError('invalid-argument', 'Invalid correction request.');
  }

  const bankSnap = await admin.database().ref(`bank_accounts/${bankAccountId}`).once('value');
  if (!bankSnap.exists()) throw new HttpsError('not-found', 'Bank account not found.');
  const bank = bankSnap.val();
  const currentBal = asNumber(bank.balance);
  const diff = newBalance - currentBal;
  if (diff === 0) {
    return { txId: null, unchanged: true };
  }
  const txId = uuidv4();
  const nowIso = new Date().toISOString();

  await admin.database().ref().update({
    [`financial_ledger/${txId}`]: {
      id: txId,
      type: diff >= 0 ? 'FUND_BANK' : 'BANK_DEDUCTION',
      amount: Math.abs(diff),
      toId: diff >= 0 ? bankAccountId : null,
      fromId: diff < 0 ? bankAccountId : null,
      toLabel: diff >= 0 ? (bank.bankName || 'Bank Account') : 'Balance Correction',
      fromLabel: diff < 0 ? (bank.bankName || 'Bank Account') : 'Balance Correction',
      createdByUid,
      notes: `BALANCE_CORRECTION: ${notes || 'Manual Adjustment'}`,
      timestamp: Date.now(),
    },
    [`bank_accounts/${bankAccountId}/balance`]: newBalance,
    [`bank_accounts/${bankAccountId}/lastUpdatedAt`]: nowIso,
  });

  return { txId };
});

exports.distributeVfCash = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const retailerId = request.data?.retailerId?.toString();
  const fromVfNumberId = request.data?.fromVfNumberId?.toString();
  const fromVfPhone = request.data?.fromVfPhone?.toString();
  const amount = asNumber(request.data?.amount);
  const fees = asNumber(request.data?.fees);
  const chargeFeesToRetailer = request.data?.chargeFeesToRetailer === true;
  const applyCredit = request.data?.applyCredit === true;
  const createdByUid = uid;
  const notes = request.data?.notes?.toString().trim() || null;
  if (!retailerId || !fromVfNumberId || !fromVfPhone || amount <= 0 || fees < 0) {
    throw new HttpsError('invalid-argument', 'Invalid distribution request.');
  }

  const db = admin.database();
  const totalDeduction = amount + fees;
  const now = new Date();
  const nowIso = now.toISOString();
  const nowTs = now.getTime();

  // ─── Phase 1: Compute retailer amounts (read-only, no lock) ──────────────
  const { retailer, actualDebtIncrease, creditUsed } = await computeDistributionAmounts({
    db, retailerId, amount, fees, chargeFeesToRetailer, applyCredit,
  });

  // ─── Phase 2: Atomically reserve VF number balance via transaction ────────
  // applyLocally:false ensures Firebase always calls handler with real server
  // data — no null optimistic phase, no spurious abort.
  const vfReservation = await updateMobileNumberUsageTransaction({
    numberId: fromVfNumberId,
    amountDelta: totalDeduction,
    direction: 'outgoing',
    timestampMs: nowTs,
    nowIso,
    requireSufficientBalance: true,
  });

  if (!vfReservation.committed) {
    // Transaction returned undefined (explicit abort) = truly insufficient balance.
    const vfNumberSnap = await db.ref(`mobile_numbers/${fromVfNumberId}`).once('value');
    if (!vfNumberSnap.exists()) throw new HttpsError('not-found', 'Vodafone number not found.');
    const currentVfBalance = getMobileNumberBalance(vfNumberSnap.val());
    throw new HttpsError(
      'failed-precondition',
      `Insufficient Vodafone balance. Available: ${currentVfBalance.toFixed(2)} EGP, required: ${totalDeduction.toFixed(2)} EGP.`
    );
  }

  // ─── Phase 3: Build and commit the full atomic multi-path write ───────────
  // Retailer balance is updated here via ServerValue.increment — these are
  // individually atomic on their own paths and don't need a transaction lock.
  // If this write fails, we roll back the VF transaction only.
  const txId = uuidv4();
  const cashTxId = uuidv4();
  const reservedVfNumber = vfReservation.snapshot.val() || {};
  const vfPhoneLabel = reservedVfNumber.phoneNumber || fromVfPhone;
  const retailerName = retailer.name || 'Retailer';

  const feeNotes = chargeFeesToRetailer && fees > 0 ? `, +${fees} Fee` : '';
  const creditNotes = creditUsed > 0 ? `, -${creditUsed} Credit Used` : '';
  const appliedNotes = notes && notes.length > 0
    ? `${notes} (Rate: ${asNumber(retailer.discountPer1000)}/1K${feeNotes}${creditNotes}, Debt +${actualDebtIncrease} EGP)`
    : `Rate: ${asNumber(retailer.discountPer1000)}/1K${feeNotes}${creditNotes}, Debt +${actualDebtIncrease} EGP`;

  const updates = {
    [`financial_ledger/${txId}`]: {
      id: txId,
      type: 'DISTRIBUTE_VFCASH',
      amount,
      fromId: fromVfNumberId,
      fromLabel: vfPhoneLabel,
      toId: retailerId,
      toLabel: retailerName,
      createdByUid,
      notes: appliedNotes,
      generatedTransactionId: cashTxId,
      timestamp: nowTs,
    },
    [`transactions/${cashTxId}`]: {
      id: cashTxId,
      phoneNumber: vfPhoneLabel,
      amount: totalDeduction,
      currency: 'EGP',
      timestamp: nowIso,
      bybitOrderId: `DIST-${txId.substring(0, 8)}`,
      status: 'completed',
      paymentMethod: 'Vodafone Distribution',
      side: 0,
      relatedLedgerId: txId,
      chatHistory: fees > 0
        ? `Automated Distribution to ${retailerName} (Includes ${fees} EGP transfer fees${chargeFeesToRetailer ? ' - charged to retailer' : ''})`
        : `Automated Distribution to ${retailerName}`,
    },
    // Retailer debt: use increment for atomic write, no transaction lock needed
    [`retailers/${retailerId}/totalAssigned`]: admin.database.ServerValue.increment(actualDebtIncrease),
    [`retailers/${retailerId}/lastUpdatedAt`]: nowIso,
  };

  // Apply credit deduction if any was used
  if (creditUsed > 0) {
    updates[`retailers/${retailerId}/credit`] = admin.database.ServerValue.increment(-creditUsed);
  }

  if (fees > 0) {
    const feeTxId = uuidv4();
    updates[`financial_ledger/${feeTxId}`] = {
      id: feeTxId,
      type: 'EXPENSE_VFCASH_FEE',
      amount: fees,
      fromId: fromVfNumberId,
      fromLabel: vfPhoneLabel,
      createdByUid,
      relatedLedgerId: txId,
      notes: chargeFeesToRetailer
        ? `Vodafone Transfer Fee for assigning ${amount} EGP to ${retailerName} (charged to retailer debt)`
        : `Vodafone Transfer Fee for assigning ${amount} EGP to ${retailerName}`,
      timestamp: nowTs,
    };
  }

  try {
    await db.ref().update(updates);
  } catch (error) {
    // Roll back only the VF balance reservation on write failure.
    // Retailer update was part of this write, so it was never applied.
    await updateMobileNumberUsageTransaction({
      numberId: fromVfNumberId,
      amountDelta: -totalDeduction,
      direction: 'outgoing',
      timestampMs: nowTs,
      nowIso,
      clampAtZero: true,
    }).catch(() => {});
    throw new HttpsError('internal', error.message || 'Unable to complete distribution.');
  }

  return { txId, creditUsed, actualDebtIncrease };
});

exports.creditReturn = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const retailerId = request.data?.retailerId?.toString();
  const vfNumberId = request.data?.vfNumberId?.toString();
  const vfPhone = request.data?.vfPhone?.toString();
  const amount = asNumber(request.data?.amount);
  const fees = asNumber(request.data?.fees);
  const createdByUid = uid;
  const notes = request.data?.notes?.toString().trim() || null;
  if (!retailerId || !vfNumberId || !vfPhone || amount <= 0 || fees < 0) {
    throw new HttpsError('invalid-argument', 'Invalid credit return request.');
  }

  const [retailerSnap, vfNumberSnap] = await Promise.all([
    admin.database().ref(`retailers/${retailerId}`).once('value'),
    admin.database().ref(`mobile_numbers/${vfNumberId}`).once('value'),
  ]);
  if (!retailerSnap.exists()) throw new HttpsError('not-found', 'Retailer not found.');
  if (!vfNumberSnap.exists()) throw new HttpsError('not-found', 'Vodafone number not found.');
  const retailer = retailerSnap.val();
  const remainingDebt = getRetailerOutstandingDebt(retailer);
  if ((amount - remainingDebt) > 0.01) {
    throw new HttpsError(
      'failed-precondition',
      `Credit return exceeds remaining retailer debt. Remaining debt: ${remainingDebt.toFixed(2)} EGP.`
    );
  }
  const now = new Date();
  const nowIso = now.toISOString();
  const nowTs = now.getTime();
  const txId = uuidv4();
  const feeTxId = uuidv4();
  const cashTxId = uuidv4();
  const totalReceived = amount + fees;
  const updates = {
    [`financial_ledger/${txId}`]: {
      id: txId,
      type: 'CREDIT_RETURN',
      amount,
      fromId: retailerId,
      fromLabel: retailer.name || 'Retailer',
      toId: vfNumberId,
      toLabel: vfPhone,
      createdByUid,
      notes: notes || 'Debt Settlement via VF Cash',
      generatedTransactionId: cashTxId,
      timestamp: nowTs,
    },
    [`transactions/${cashTxId}`]: {
      id: cashTxId,
      phoneNumber: vfPhone,
      amount: totalReceived,
      currency: 'EGP',
      timestamp: nowIso,
      bybitOrderId: `CRTN-${txId.substring(0, 8)}`,
      status: 'completed',
      paymentMethod: 'VF Credit Return',
      side: 1,
      relatedLedgerId: txId,
      chatHistory: `Credit Return from ${retailer.name} (Amount: ${amount}, Fee: ${fees})`,
    },
    [`retailers/${retailerId}/totalCollected`]: admin.database.ServerValue.increment(amount),
    [`retailers/${retailerId}/lastUpdatedAt`]: nowIso,
  };
  applyMobileNumberUsageDelta(updates, {
    numberId: vfNumberId,
    amountDelta: totalReceived,
    direction: 'incoming',
    timestampMs: nowTs,
    nowIso,
  });

  if (fees > 0) {
    updates[`financial_ledger/${feeTxId}`] = {
      id: feeTxId,
      type: 'CREDIT_RETURN_FEE',
      amount: fees,
      fromId: retailerId,
      fromLabel: retailer.name || 'Retailer',
      toId: vfNumberId,
      toLabel: vfPhone,
      createdByUid,
      relatedLedgerId: txId,
      notes: 'Credit Return Fee',
      timestamp: nowTs,
    };
  }

  await admin.database().ref().update(updates);
  return { txId };
});
function buildCorrectionNote(existingNotes, originalAmount, correctAmount, reason) {
  const base = (existingNotes || '').trim();
  const detail = reason
    ? `Corrected from ${originalAmount} to ${correctAmount}. Reason: ${reason}`
    : `Corrected from ${originalAmount} to ${correctAmount}`;
  return base ? `${base} (${detail})` : detail;
}

function parseCollectCreditPortion(tx) {
  const explicit = asNumber(tx.creditPortion);
  if (explicit > 0) return explicit;
  const notes = tx.notes ? tx.notes.toString() : '';
  const match = notes.match(/\(\+([0-9]+(?:\.[0-9]+)?) EGP added to Credit\)/i);
  return match ? asNumber(match[1]) : 0;
}

function stripCollectCreditNote(notes) {
  return (notes || '')
    .replace(/\s*\(\+[0-9]+(?:\.[0-9]+)? EGP added to Credit\)/ig, '')
    .trim();
}

function parseDistributionDebtIncrease(notes, fallbackAmount) {
  const noteText = notes ? notes.toString() : '';
  const match = noteText.match(/Debt \+([0-9]+(?:\.[0-9]+)?) EGP/i);
  return match ? asNumber(match[1]) : fallbackAmount;
}

function parseDistributionCreditUsed(notes) {
  const noteText = notes ? notes.toString() : '';
  const match = noteText.match(/-([0-9]+(?:\.[0-9]+)?) Credit Used/i);
  return match ? asNumber(match[1]) : 0;
}


exports.correctFinancialTransaction = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const transactionId = request.data?.transactionId?.toString();
  const correctAmount = asNumber(request.data?.correctAmount);
  const reason = request.data?.reason?.toString().trim() || null;
  if (!transactionId || correctAmount <= 0) {
    throw new HttpsError('invalid-argument', 'Invalid correction request.');
  }

  const db = admin.database();
  const txSnap = await db.ref(`financial_ledger/${transactionId}`).once('value');
  if (!txSnap.exists()) throw new HttpsError('not-found', 'Transaction not found.');
  const originalTx = txSnap.val();
  const originalAmount = asNumber(originalTx.amount);
  const diff = correctAmount - originalAmount;
  if (diff === 0) {
    return { unchanged: true };
  }

  const type = originalTx.type ? originalTx.type.toString() : '';
  if (!['COLLECT_CASH', 'DEPOSIT_TO_BANK', 'CREDIT_RETURN'].includes(type)) {
    throw new HttpsError('failed-precondition', 'This transaction type cannot be corrected here.');
  }

  const adjustmentId = uuidv4();
  const nowIso = new Date().toISOString();
  const updates = {
    [`financial_ledger/${transactionId}/amount`]: correctAmount,
    [`financial_ledger/${transactionId}/notes`]: buildCorrectionNote(originalTx.notes, originalAmount, correctAmount, reason),
    [`financial_ledger/${adjustmentId}`]: {
      id: adjustmentId,
      type: 'ADMIN_ADJUSTMENT',
      amount: Math.abs(diff),
      fromId: originalTx.fromId || null,
      fromLabel: originalTx.fromLabel || null,
      toId: originalTx.toId || null,
      toLabel: originalTx.toLabel || null,
      bybitOrderId: originalTx.bybitOrderId || null,
      notes: reason
        ? `CORRECTION for ${transactionId}: ${reason}`
        : `CORRECTION for ${transactionId}: amount adjusted from ${originalAmount} to ${correctAmount}`,
      createdByUid: uid,
      timestamp: Date.now(),
    },
  };

  if (type === 'COLLECT_CASH') {
    const collectorId = originalTx.toId ? originalTx.toId.toString() : '';
    const retailerId = originalTx.fromId ? originalTx.fromId.toString() : '';
    if (!collectorId || !retailerId) {
      throw new HttpsError('failed-precondition', 'Collect transaction is missing collector or retailer.');
    }

    const [collectorSnap, retailerSnap] = await Promise.all([
      db.ref(`collectors/${collectorId}`).once('value'),
      db.ref(`retailers/${retailerId}`).once('value'),
    ]);
    if (!collectorSnap.exists() || !retailerSnap.exists()) {
      throw new HttpsError('not-found', 'Collector or retailer not found.');
    }

    const collector = collectorSnap.val();
    const retailer = retailerSnap.val();
    const oldCreditPortion = parseCollectCreditPortion(originalTx);
    const oldCollectedPortion = Math.max(0, originalAmount - oldCreditPortion);
    let newCollectedPortion = correctAmount;
    let newCreditPortion = 0;

    if (oldCreditPortion > 0) {
      const pendingDebtAtCollection = oldCollectedPortion;
      newCollectedPortion = Math.min(correctAmount, pendingDebtAtCollection);
      newCreditPortion = correctAmount - newCollectedPortion;
    } else if (correctAmount > originalAmount) {
      throw new HttpsError('failed-precondition', 'Cannot safely increase this collection because the original debt split is unknown.');
    }

    const collectedDelta = newCollectedPortion - oldCollectedPortion;
    const creditDelta = newCreditPortion - oldCreditPortion;
    const retailerCollected = asNumber(retailer.totalCollected);
    const retailerCredit = asNumber(retailer.credit);
    const collectorCash = asNumber(collector.cashOnHand);
    const collectorTotalCollected = asNumber(collector.totalCollected);

    if (retailerCollected + collectedDelta < 0 || retailerCredit + creditDelta < 0) {
      throw new HttpsError('failed-precondition', 'Retailer balance would become invalid.');
    }
    if (collectorCash + diff < 0 || collectorTotalCollected + diff < 0) {
      throw new HttpsError('failed-precondition', 'Collector balance would become invalid.');
    }

    const baseNotes = stripCollectCreditNote(originalTx.notes);
    const creditNote = newCreditPortion > 0 ? `(+${newCreditPortion.toFixed(0)} EGP added to Credit)` : '';
    const noteBody = [baseNotes, creditNote].filter((value) => value && value.length > 0).join(' ').trim();

    updates[`financial_ledger/${transactionId}/notes`] = buildCorrectionNote(noteBody, originalAmount, correctAmount, reason);
    updates[`financial_ledger/${transactionId}/collectedPortion`] = newCollectedPortion;
    updates[`financial_ledger/${transactionId}/creditPortion`] = newCreditPortion;
    updates[`collectors/${collectorId}/cashOnHand`] = admin.database.ServerValue.increment(diff);
    updates[`collectors/${collectorId}/totalCollected`] = admin.database.ServerValue.increment(diff);
    updates[`collectors/${collectorId}/lastUpdatedAt`] = nowIso;
    updates[`retailers/${retailerId}/lastUpdatedAt`] = nowIso;
    if (collectedDelta !== 0) {
      updates[`retailers/${retailerId}/totalCollected`] = admin.database.ServerValue.increment(collectedDelta);
    }
    if (creditDelta !== 0) {
      updates[`retailers/${retailerId}/credit`] = admin.database.ServerValue.increment(creditDelta);
    }
  } else if (type === 'DEPOSIT_TO_BANK') {
    const collectorId = originalTx.fromId ? originalTx.fromId.toString() : '';
    const bankId = originalTx.toId ? originalTx.toId.toString() : '';
    if (!collectorId || !bankId) {
      throw new HttpsError('failed-precondition', 'Deposit transaction is missing collector or bank.');
    }

    const [collectorSnap, bankSnap] = await Promise.all([
      db.ref(`collectors/${collectorId}`).once('value'),
      db.ref(`bank_accounts/${bankId}`).once('value'),
    ]);
    if (!collectorSnap.exists() || !bankSnap.exists()) {
      throw new HttpsError('not-found', 'Collector or bank account not found.');
    }

    const collector = collectorSnap.val();
    const bank = bankSnap.val();
    if (asNumber(bank.balance) + diff < 0 || asNumber(collector.cashOnHand) - diff < 0 || asNumber(collector.totalDeposited) + diff < 0) {
      throw new HttpsError('failed-precondition', 'Correction would make a balance invalid.');
    }

    updates[`bank_accounts/${bankId}/balance`] = admin.database.ServerValue.increment(diff);
    updates[`bank_accounts/${bankId}/lastUpdatedAt`] = nowIso;
    updates[`collectors/${collectorId}/cashOnHand`] = admin.database.ServerValue.increment(-diff);
    updates[`collectors/${collectorId}/totalDeposited`] = admin.database.ServerValue.increment(diff);
    updates[`collectors/${collectorId}/lastUpdatedAt`] = nowIso;
  } else if (type === 'CREDIT_RETURN') {
    const retailerId = originalTx.fromId ? originalTx.fromId.toString() : '';
    const vfNumberId = originalTx.toId ? originalTx.toId.toString() : '';
    if (!retailerId) {
      throw new HttpsError('failed-precondition', 'Credit return is missing retailer information.');
    }

    const [retailerSnap, vfNumberSnap] = await Promise.all([
      db.ref(`retailers/${retailerId}`).once('value'),
      vfNumberId ? db.ref(`mobile_numbers/${vfNumberId}`).once('value') : Promise.resolve(null),
    ]);
    if (!retailerSnap.exists()) throw new HttpsError('not-found', 'Retailer not found.');
    const retailer = retailerSnap.val();
    const remainingDebtBeforeReturn = getRetailerOutstandingDebt(retailer) + originalAmount;
    if ((correctAmount - remainingDebtBeforeReturn) > 0.01) {
      throw new HttpsError(
        'failed-precondition',
        `Corrected amount exceeds the retailer debt that existed before this return. Max allowed: ${remainingDebtBeforeReturn.toFixed(2)} EGP.`
      );
    }
    if (asNumber(retailer.totalCollected) + diff < 0) {
      throw new HttpsError('failed-precondition', 'Retailer collected total would become invalid.');
    }

    const generatedTransactions = await getGeneratedTransactions(`CRTN-${transactionId.substring(0, 8)}`);
    if (generatedTransactions.length !== 1) {
      throw new HttpsError('failed-precondition', 'Credit return is missing its generated VF transaction.');
    }

    const generatedTransaction = generatedTransactions[0];
    const generatedAmount = asNumber(generatedTransaction.value.amount);
    const retainedFee = Math.max(0, generatedAmount - originalAmount);
    const correctedGeneratedAmount = correctAmount + retainedFee;
    if (correctedGeneratedAmount <= 0) {
      throw new HttpsError('failed-precondition', 'Corrected cash receipt would become invalid.');
    }

    updates[`retailers/${retailerId}/totalCollected`] = admin.database.ServerValue.increment(diff);
    updates[`retailers/${retailerId}/lastUpdatedAt`] = nowIso;
    updates[`transactions/${generatedTransaction.key}/amount`] = correctedGeneratedAmount;
    updates[`transactions/${generatedTransaction.key}/chatHistory`] = `Credit Return from ${retailer.name} (Amount: ${correctAmount}, Fee: ${retainedFee})`;
    if (vfNumberSnap && vfNumberSnap.exists()) {
      applyMobileNumberUsageDelta(updates, {
        numberId: vfNumberId,
        amountDelta: diff,
        direction: 'incoming',
        timestampMs: getTransactionTimestampMs(generatedTransaction.value),
        nowIso,
      });
    }
  }

  await db.ref().update(updates);
  return { adjustmentId };
});
exports.deleteFinancialTransaction = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const transactionId = request.data?.transactionId?.toString();
  if (!transactionId) {
    throw new HttpsError('invalid-argument', 'Transaction id is required.');
  }

  const db = admin.database();
  const txSnap = await db.ref(`financial_ledger/${transactionId}`).once('value');
  if (!txSnap.exists()) throw new HttpsError('not-found', 'Transaction not found.');
  const tx = txSnap.val();
  const type = tx.type ? tx.type.toString() : '';
  const amount = asNumber(tx.amount);
  const nowIso = new Date().toISOString();
  const updates = {
    [`financial_ledger/${transactionId}`]: null,
  };

  if (type === 'COLLECT_CASH') {
    const retailerId = tx.fromId ? tx.fromId.toString() : '';
    const collectorId = tx.toId ? tx.toId.toString() : '';
    if (!retailerId || !collectorId) {
      throw new HttpsError('failed-precondition', 'Collect transaction is missing collector or retailer.');
    }
    const [collectorSnap, retailerSnap] = await Promise.all([
      db.ref(`collectors/${collectorId}`).once('value'),
      db.ref(`retailers/${retailerId}`).once('value'),
    ]);
    if (!collectorSnap.exists() || !retailerSnap.exists()) {
      throw new HttpsError('not-found', 'Collector or retailer not found.');
    }
    const collector = collectorSnap.val();
    const retailer = retailerSnap.val();
    const creditPortion = parseCollectCreditPortion(tx);
    const collectedPortion = Math.max(0, amount - creditPortion);
    if (asNumber(collector.cashOnHand) < amount || asNumber(collector.totalCollected) < amount) {
      throw new HttpsError('failed-precondition', 'Collector balances are too low to reverse this transaction.');
    }
    if (asNumber(retailer.totalCollected) < collectedPortion || asNumber(retailer.credit) < creditPortion) {
      throw new HttpsError('failed-precondition', 'Retailer balances are too low to reverse this transaction.');
    }
    updates[`collectors/${collectorId}/cashOnHand`] = admin.database.ServerValue.increment(-amount);
    updates[`collectors/${collectorId}/totalCollected`] = admin.database.ServerValue.increment(-amount);
    updates[`collectors/${collectorId}/lastUpdatedAt`] = nowIso;
    if (collectedPortion > 0) {
      updates[`retailers/${retailerId}/totalCollected`] = admin.database.ServerValue.increment(-collectedPortion);
    }
    if (creditPortion > 0) {
      updates[`retailers/${retailerId}/credit`] = admin.database.ServerValue.increment(-creditPortion);
    }
    updates[`retailers/${retailerId}/lastUpdatedAt`] = nowIso;
  } else if (type === 'DEPOSIT_TO_BANK') {
    const collectorId = tx.fromId ? tx.fromId.toString() : '';
    const bankId = tx.toId ? tx.toId.toString() : '';
    if (!collectorId || !bankId) {
      throw new HttpsError('failed-precondition', 'Deposit transaction is missing collector or bank.');
    }
    const [collectorSnap, bankSnap] = await Promise.all([
      db.ref(`collectors/${collectorId}`).once('value'),
      db.ref(`bank_accounts/${bankId}`).once('value'),
    ]);
    if (!collectorSnap.exists() || !bankSnap.exists()) {
      throw new HttpsError('not-found', 'Collector or bank account not found.');
    }
    const collector = collectorSnap.val();
    const bank = bankSnap.val();
    if (asNumber(bank.balance) < amount || asNumber(collector.totalDeposited) < amount) {
      throw new HttpsError('failed-precondition', 'Balances are too low to reverse this deposit.');
    }
    updates[`bank_accounts/${bankId}/balance`] = admin.database.ServerValue.increment(-amount);
    updates[`bank_accounts/${bankId}/lastUpdatedAt`] = nowIso;
    updates[`collectors/${collectorId}/cashOnHand`] = admin.database.ServerValue.increment(amount);
    updates[`collectors/${collectorId}/totalDeposited`] = admin.database.ServerValue.increment(-amount);
    updates[`collectors/${collectorId}/lastUpdatedAt`] = nowIso;
  } else if (type === 'DEPOSIT_TO_VFCASH') {
    const collectorId = tx.fromId ? tx.fromId.toString() : '';
    const vfNumberId = tx.toId ? tx.toId.toString() : '';
    if (!collectorId || !vfNumberId) {
      throw new HttpsError('failed-precondition', 'Vodafone deposit is missing collector or VF number.');
    }

    const [collectorSnap, vfNumberSnap, generatedTransactions, relatedProfitEntries] = await Promise.all([
      db.ref(`collectors/${collectorId}`).once('value'),
      db.ref(`mobile_numbers/${vfNumberId}`).once('value'),
      getGeneratedTransactions(`CLDV-${transactionId.substring(0, 8)}`),
      getRelatedLedgerEntries(transactionId, ['VFCASH_RETAIL_PROFIT']),
    ]);
    if (!collectorSnap.exists()) {
      throw new HttpsError('not-found', 'Collector not found.');
    }

    const collector = collectorSnap.val();
    if (asNumber(collector.totalDeposited) < amount) {
      throw new HttpsError('failed-precondition', 'Collector deposited total is too low to reverse this Vodafone deposit.');
    }

    updates[`collectors/${collectorId}/cashOnHand`] = admin.database.ServerValue.increment(amount);
    updates[`collectors/${collectorId}/totalDeposited`] = admin.database.ServerValue.increment(-amount);
    updates[`collectors/${collectorId}/lastUpdatedAt`] = nowIso;
    Object.assign(updates, buildGeneratedTransactionRemovals(generatedTransactions));
    Object.assign(updates, buildLedgerRemovals(relatedProfitEntries));
    if (vfNumberSnap && vfNumberSnap.exists()) {
      if (generatedTransactions.length > 0) {
        generatedTransactions.forEach((generatedTransaction) => {
          applyMobileNumberUsageDelta(updates, {
            numberId: vfNumberId,
            amountDelta: -asNumber(generatedTransaction.value.amount),
            direction: 'incoming',
            timestampMs: getTransactionTimestampMs(generatedTransaction.value),
            nowIso,
          });
        });
      } else {
        const fallbackIncomingAmount =
          asNumber(tx.transferredAmount) ||
          (amount + sumEntryAmounts(relatedProfitEntries));
        applyMobileNumberUsageDelta(updates, {
          numberId: vfNumberId,
          amountDelta: -fallbackIncomingAmount,
          direction: 'incoming',
          timestampMs: getTransactionTimestampMs(tx),
          nowIso,
        });
      }
    }
  } else if (type === 'DISTRIBUTE_VFCASH') {
    const retailerId = tx.toId ? tx.toId.toString() : '';
    const vfNumberId = tx.fromId ? tx.fromId.toString() : '';
    if (!retailerId) {
      throw new HttpsError('failed-precondition', 'Distribution transaction is missing retailer.');
    }

    const [retailerSnap, vfNumberSnap, generatedTransactions, relatedFeeEntries] = await Promise.all([
      db.ref(`retailers/${retailerId}`).once('value'),
      vfNumberId ? db.ref(`mobile_numbers/${vfNumberId}`).once('value') : Promise.resolve(null),
      getGeneratedTransactions(`DIST-${transactionId.substring(0, 8)}`),
      getRelatedLedgerEntries(transactionId, ['EXPENSE_VFCASH_FEE']),
    ]);
    if (!retailerSnap.exists()) throw new HttpsError('not-found', 'Retailer not found.');
    const retailer = retailerSnap.val();
    const debtIncrease = parseDistributionDebtIncrease(tx.notes, amount);
    const creditUsed = parseDistributionCreditUsed(tx.notes);
    if (asNumber(retailer.totalAssigned) < debtIncrease) {
      throw new HttpsError('failed-precondition', 'Retailer assigned total is too low to reverse this distribution.');
    }
    updates[`retailers/${retailerId}/totalAssigned`] = admin.database.ServerValue.increment(-debtIncrease);
    updates[`retailers/${retailerId}/lastUpdatedAt`] = nowIso;
    if (creditUsed > 0) {
      updates[`retailers/${retailerId}/credit`] = admin.database.ServerValue.increment(creditUsed);
    }
    Object.assign(updates, buildGeneratedTransactionRemovals(generatedTransactions));
    Object.assign(updates, buildLedgerRemovals(relatedFeeEntries));
    if (vfNumberSnap && vfNumberSnap.exists()) {
      if (generatedTransactions.length > 0) {
        generatedTransactions.forEach((generatedTransaction) => {
          applyMobileNumberUsageDelta(updates, {
            numberId: vfNumberId,
            amountDelta: -asNumber(generatedTransaction.value.amount),
            direction: 'outgoing',
            timestampMs: getTransactionTimestampMs(generatedTransaction.value),
            nowIso,
          });
        });
      } else {
        const fallbackOutgoingAmount = amount + sumEntryAmounts(relatedFeeEntries);
        applyMobileNumberUsageDelta(updates, {
          numberId: vfNumberId,
          amountDelta: -fallbackOutgoingAmount,
          direction: 'outgoing',
          timestampMs: getTransactionTimestampMs(tx),
          nowIso,
        });
      }
    }
  } else if (type === 'FUND_BANK') {
    const bankId = tx.toId ? tx.toId.toString() : '';
    if (!bankId) throw new HttpsError('failed-precondition', 'Fund bank transaction is missing bank account.');
    const bankSnap = await db.ref(`bank_accounts/${bankId}`).once('value');
    if (!bankSnap.exists()) throw new HttpsError('not-found', 'Bank account not found.');
    if (asNumber(bankSnap.val().balance) < amount) {
      throw new HttpsError('failed-precondition', 'Bank balance is too low to reverse this funding transaction.');
    }
    updates[`bank_accounts/${bankId}/balance`] = admin.database.ServerValue.increment(-amount);
    updates[`bank_accounts/${bankId}/lastUpdatedAt`] = nowIso;
  } else if (type === 'BUY_USDT') {
    const bankId = tx.fromId ? tx.fromId.toString() : '';
    if (bankId) {
      updates[`bank_accounts/${bankId}/balance`] = admin.database.ServerValue.increment(amount);
      updates[`bank_accounts/${bankId}/lastUpdatedAt`] = nowIso;
    }
  } else if (type === 'CREDIT_RETURN') {
    const retailerId = tx.fromId ? tx.fromId.toString() : '';
    const vfNumberId = tx.toId ? tx.toId.toString() : '';
    if (!retailerId) throw new HttpsError('failed-precondition', 'Credit return transaction is missing retailer.');

    const [retailerSnap, vfNumberSnap, generatedTransactions, relatedFeeEntries] = await Promise.all([
      db.ref(`retailers/${retailerId}`).once('value'),
      vfNumberId ? db.ref(`mobile_numbers/${vfNumberId}`).once('value') : Promise.resolve(null),
      getGeneratedTransactions(`CRTN-${transactionId.substring(0, 8)}`),
      getRelatedLedgerEntries(transactionId, ['CREDIT_RETURN_FEE']),
    ]);
    if (!retailerSnap.exists()) throw new HttpsError('not-found', 'Retailer not found.');
    if (asNumber(retailerSnap.val().totalCollected) < amount) {
      throw new HttpsError('failed-precondition', 'Retailer collected total is too low to reverse this credit return.');
    }
    updates[`retailers/${retailerId}/totalCollected`] = admin.database.ServerValue.increment(-amount);
    updates[`retailers/${retailerId}/lastUpdatedAt`] = nowIso;
    Object.assign(updates, buildGeneratedTransactionRemovals(generatedTransactions));
    Object.assign(updates, buildLedgerRemovals(relatedFeeEntries));
    if (vfNumberSnap && vfNumberSnap.exists()) {
      if (generatedTransactions.length > 0) {
        generatedTransactions.forEach((generatedTransaction) => {
          applyMobileNumberUsageDelta(updates, {
            numberId: vfNumberId,
            amountDelta: -asNumber(generatedTransaction.value.amount),
            direction: 'incoming',
            timestampMs: getTransactionTimestampMs(generatedTransaction.value),
            nowIso,
          });
        });
      } else {
        const fallbackIncomingAmount = amount + sumEntryAmounts(relatedFeeEntries);
        applyMobileNumberUsageDelta(updates, {
          numberId: vfNumberId,
          amountDelta: -fallbackIncomingAmount,
          direction: 'incoming',
          timestampMs: getTransactionTimestampMs(tx),
          nowIso,
        });
      }
    }
  } else if (type === 'CREDIT_RETURN_FEE') {
  } else if (type === 'BANK_DEDUCTION') {
    const bankId = tx.fromId ? tx.fromId.toString() : '';
    if (!bankId) throw new HttpsError('failed-precondition', 'Bank deduction transaction is missing bank account.');
    updates[`bank_accounts/${bankId}/balance`] = admin.database.ServerValue.increment(amount);
    updates[`bank_accounts/${bankId}/lastUpdatedAt`] = nowIso;
  } else {
    throw new HttpsError('failed-precondition', 'This transaction type cannot be deleted here.');
  }

  await db.ref().update(updates);
  return { deleted: true };
});

exports.processRetailerRequest = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const { portalUserUid, requestId, status, proofImageUrl, adminNotes } = request.data;
  if (!portalUserUid || !requestId || !status) {
    throw new HttpsError('invalid-argument', 'Missing core request fields.');
  }

  const db = admin.database();
  const now = new Date();
  const nowIso = now.toISOString();
  const nowTs = now.getTime();

  // 0. Status Check (Duplicate Prevention)
  const reqSnap = await db.ref(`retailer_portal/${portalUserUid}/requests/${requestId}`).once('value');
  if (!reqSnap.exists()) {
    throw new HttpsError('not-found', 'Retailer request not found.');
  }
  const rData = reqSnap.val();
  if (rData.status === 'COMPLETED' || rData.status === 'REJECTED') {
    throw new HttpsError('failed-precondition', 'This request has already been finalized.');
  }

  // Handle REJECTED
  if (status === 'REJECTED') {
    const updates = {
      [`retailer_portal/${portalUserUid}/requests/${requestId}/status`]: 'REJECTED',
      [`retailer_portal/${portalUserUid}/requests/${requestId}/rejectedReason`]: adminNotes || null,
      [`retailer_portal/${portalUserUid}/requests/${requestId}/completedAt`]: nowTs,
      [`retailer_portal/${portalUserUid}/requests/${requestId}/completedByUid`]: uid,
    };
    await db.ref().update(updates);
    return { success: true };
  }

  // Handle COMPLETED
  // Needs all the distributeVfCash fields:
  const retailerId = request.data?.retailerId?.toString();
  const fromVfNumberId = request.data?.fromVfNumberId?.toString();
  const fromVfPhone = request.data?.fromVfPhone?.toString();
  const amount = asNumber(request.data?.amount);
  const fees = asNumber(request.data?.fees);
  const chargeFeesToRetailer = request.data?.chargeFeesToRetailer === true;
  const applyCredit = request.data?.applyCredit === true;

  if (!retailerId || !fromVfNumberId || !fromVfPhone || amount <= 0 || fees < 0) {
    throw new HttpsError('invalid-argument', 'Invalid distribution request.');
  }

  const totalDeduction = amount + fees;

  const { retailer, actualDebtIncrease, creditUsed } = await computeDistributionAmounts({
    db, retailerId, amount, fees, chargeFeesToRetailer, applyCredit,
  });

  const vfReservation = await updateMobileNumberUsageTransaction({
    numberId: fromVfNumberId,
    amountDelta: totalDeduction,
    direction: 'outgoing',
    timestampMs: nowTs,
    nowIso,
    requireSufficientBalance: true,
  });

  if (!vfReservation.committed) {
    const vfNumberSnap = await db.ref(`mobile_numbers/${fromVfNumberId}`).once('value');
    if (!vfNumberSnap.exists()) throw new HttpsError('not-found', 'Vodafone number not found.');
    const currentVfBalance = getMobileNumberBalance(vfNumberSnap.val());
    throw new HttpsError(
      'failed-precondition',
      `Insufficient Vodafone balance. Available: ${currentVfBalance.toFixed(2)} EGP, required: ${totalDeduction.toFixed(2)} EGP.`
    );
  }

  const txId = uuidv4();
  const cashTxId = uuidv4();
  const reservedVfNumber = vfReservation.snapshot.val() || {};
  const vfPhoneLabel = reservedVfNumber.phoneNumber || fromVfPhone;
  const retailerName = retailer.name || 'Retailer';

  const feeNotes = chargeFeesToRetailer && fees > 0 ? `, +${fees} Fee` : '';
  const creditNotes = creditUsed > 0 ? `, -${creditUsed} Credit Used` : '';
  const appliedNotes = adminNotes && adminNotes.length > 0
    ? `${adminNotes} (Rate: ${asNumber(retailer.discountPer1000)}/1K${feeNotes}${creditNotes}, Debt +${actualDebtIncrease} EGP)`
    : `Rate: ${asNumber(retailer.discountPer1000)}/1K${feeNotes}${creditNotes}, Debt +${actualDebtIncrease} EGP`;

  const updates = {
    // 1. Transaction & Ledger updates (Identical to distributeVfCash)
    [`financial_ledger/${txId}`]: {
      id: txId,
      type: 'DISTRIBUTE_VFCASH',
      amount,
      fromId: fromVfNumberId,
      fromLabel: vfPhoneLabel,
      toId: retailerId,
      toLabel: retailerName,
      createdByUid: uid,
      notes: appliedNotes,
      generatedTransactionId: cashTxId,
      timestamp: nowTs,
    },
    [`transactions/${cashTxId}`]: {
      id: cashTxId,
      phoneNumber: vfPhoneLabel,
      amount: totalDeduction,
      currency: 'EGP',
      timestamp: nowIso,
      bybitOrderId: `DIST-${txId.substring(0, 8)}`,
      status: 'completed',
      paymentMethod: 'Vodafone Distribution',
      side: 0,
      relatedLedgerId: txId,
      chatHistory: fees > 0
        ? `Automated Distribution to ${retailerName} (Includes ${fees} EGP transfer fees${chargeFeesToRetailer ? ' - charged to retailer' : ''})`
        : `Automated Distribution to ${retailerName}`,
    },
    [`retailers/${retailerId}/totalAssigned`]: admin.database.ServerValue.increment(actualDebtIncrease),
    [`retailers/${retailerId}/lastUpdatedAt`]: nowIso,

    // 2. Request Completion updates
    [`retailer_portal/${portalUserUid}/requests/${requestId}/status`]: 'COMPLETED',
    [`retailer_portal/${portalUserUid}/requests/${requestId}/assignedAmount`]: amount,
    [`retailer_portal/${portalUserUid}/requests/${requestId}/adminNotes`]: adminNotes || null,
    [`retailer_portal/${portalUserUid}/requests/${requestId}/proofImageUrl`]: proofImageUrl || null,
    [`retailer_portal/${portalUserUid}/requests/${requestId}/completedAt`]: nowTs,
    [`retailer_portal/${portalUserUid}/requests/${requestId}/completedByUid`]: uid,
  };

  if (creditUsed > 0) {
    updates[`retailers/${retailerId}/credit`] = admin.database.ServerValue.increment(-creditUsed);
  }

  if (fees > 0) {
    const feeTxId = uuidv4();
    updates[`financial_ledger/${feeTxId}`] = {
      id: feeTxId,
      type: 'EXPENSE_VFCASH_FEE',
      amount: fees,
      fromId: fromVfNumberId,
      fromLabel: vfPhoneLabel,
      createdByUid: uid,
      relatedLedgerId: txId,
      notes: chargeFeesToRetailer
        ? `Vodafone Transfer Fee for assigning ${amount} EGP to ${retailerName} (charged to retailer debt)`
        : `Vodafone Transfer Fee for assigning ${amount} EGP to ${retailerName}`,
      timestamp: nowTs,
    };
  }

  try {
    await db.ref().update(updates);
    return { success: true };
  } catch (error) {
    await updateMobileNumberUsageTransaction({
      numberId: fromVfNumberId,
      amountDelta: -totalDeduction,
      direction: 'incoming',
      timestampMs: nowTs,
      nowIso,
      requireSufficientBalance: false,
    });
    throw new HttpsError('internal', 'Distribution transaction failed globally. Rolled back VF lock.');
  }
});
