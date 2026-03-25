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

  const [retailerSnap, vfNumberSnap] = await Promise.all([
    admin.database().ref(`retailers/${retailerId}`).once('value'),
    admin.database().ref(`mobile_numbers/${fromVfNumberId}`).once('value'),
  ]);
  if (!retailerSnap.exists()) throw new HttpsError('not-found', 'Retailer not found.');
  if (!vfNumberSnap.exists()) throw new HttpsError('not-found', 'Vodafone number not found.');

  const retailer = retailerSnap.val();
  const vfNumber = vfNumberSnap.val();
  const totalDeduction = amount + fees;
  const currentVfBalance = getMobileNumberBalance(vfNumber);
  if ((totalDeduction - currentVfBalance) > 0.01) {
    throw new HttpsError(
      'failed-precondition',
      `Insufficient Vodafone balance. Available: ${currentVfBalance.toFixed(2)} EGP, required: ${totalDeduction.toFixed(2)} EGP.`
    );
  }

  const discountAmount = (amount / 1000.0) * asNumber(retailer.discountPer1000);
  const feeToCharge = chargeFeesToRetailer ? fees : 0.0;
  let actualDebtIncrease = Math.ceil(amount + discountAmount + feeToCharge);

  let creditUsed = 0.0;
  const currentCredit = asNumber(retailer.credit);
  if (applyCredit && currentCredit > 0) {
    creditUsed = Math.min(currentCredit, actualDebtIncrease);
    actualDebtIncrease -= creditUsed;
  }

  const feeNotes = chargeFeesToRetailer && fees > 0 ? `, +${fees} Fee` : '';
  const creditNotes = creditUsed > 0 ? `, -${creditUsed} Credit Used` : '';
  const appliedNotes = notes && notes.length > 0
    ? `${notes} (Rate: ${asNumber(retailer.discountPer1000)}/1K${feeNotes}${creditNotes}, Debt +${actualDebtIncrease} EGP)`
    : `Rate: ${asNumber(retailer.discountPer1000)}/1K${feeNotes}${creditNotes}, Debt +${actualDebtIncrease} EGP`;

  const txId = uuidv4();
  const cashTxId = uuidv4();
  const now = new Date();
  const nowIso = now.toISOString();
  const nowTs = now.getTime();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime();
  const updates = {
    [`financial_ledger/${txId}`]: {
      id: txId,
      type: 'DISTRIBUTE_VFCASH',
      amount,
      fromId: fromVfNumberId,
      fromLabel: fromVfPhone,
      toId: retailerId,
      toLabel: retailer.name || 'Retailer',
      createdByUid,
      notes: appliedNotes,
      timestamp: nowTs,
    },
    [`transactions/${cashTxId}`]: {
      id: cashTxId,
      phoneNumber: fromVfPhone,
      amount: totalDeduction,
      currency: 'EGP',
      timestamp: nowIso,
      bybitOrderId: `DIST-${txId.substring(0, 8)}`,
      status: 'completed',
      paymentMethod: 'Vodafone Distribution',
      side: 0,
      chatHistory: fees > 0
        ? `Automated Distribution to ${retailer.name} (Includes ${fees} EGP transfer fees${chargeFeesToRetailer ? ' - charged to retailer' : ''})`
        : `Automated Distribution to ${retailer.name}`,
    },
    [`retailers/${retailerId}/totalAssigned`]: admin.database.ServerValue.increment(actualDebtIncrease),
    [`retailers/${retailerId}/lastUpdatedAt`]: nowIso,
    [`mobile_numbers/${fromVfNumberId}/outTotalUsed`]: admin.database.ServerValue.increment(totalDeduction),
    [`mobile_numbers/${fromVfNumberId}/lastUpdatedAt`]: nowIso,
    ...(nowTs >= todayStart
      ? { [`mobile_numbers/${fromVfNumberId}/outDailyUsed`]: admin.database.ServerValue.increment(totalDeduction) }
      : {}),
    ...(nowTs >= monthStart
      ? { [`mobile_numbers/${fromVfNumberId}/outMonthlyUsed`]: admin.database.ServerValue.increment(totalDeduction) }
      : {}),
  };

  if (creditUsed > 0) {
    updates[`retailers/${retailerId}/credit`] = currentCredit - creditUsed;
  }

  if (fees > 0) {
    const feeTxId = uuidv4();
    updates[`financial_ledger/${feeTxId}`] = {
      id: feeTxId,
      type: 'EXPENSE_VFCASH_FEE',
      amount: fees,
      fromId: fromVfNumberId,
      fromLabel: fromVfPhone,
      createdByUid,
      notes: chargeFeesToRetailer
        ? `Vodafone Transfer Fee for assigning ${amount} EGP to ${retailer.name} (charged to retailer debt)`
        : `Vodafone Transfer Fee for assigning ${amount} EGP to ${retailer.name}`,
      timestamp: nowTs,
    };
  }

  await admin.database().ref().update(updates);
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

  const retailerSnap = await admin.database().ref(`retailers/${retailerId}`).once('value');
  if (!retailerSnap.exists()) throw new HttpsError('not-found', 'Retailer not found.');
  const retailer = retailerSnap.val();
  const nowIso = new Date().toISOString();
  const nowTs = Date.now();
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
      chatHistory: `Credit Return from ${retailer.name} (Amount: ${amount}, Fee: ${fees})`,
    },
    [`retailers/${retailerId}/totalCollected`]: admin.database.ServerValue.increment(amount),
    [`retailers/${retailerId}/lastUpdatedAt`]: nowIso,
  };

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

async function removeGeneratedTransaction(prefix) {
  const snap = await admin.database().ref('transactions').orderByChild('bybitOrderId').equalTo(prefix).once('value');
  if (!snap.exists()) return {};
  const removals = {};
  Object.keys(snap.val()).forEach((key) => {
    removals[`transactions/${key}`] = null;
  });
  return removals;
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
    if (!retailerId) {
      throw new HttpsError('failed-precondition', 'Credit return is missing retailer information.');
    }
    const retailerSnap = await db.ref(`retailers/${retailerId}`).once('value');
    if (!retailerSnap.exists()) throw new HttpsError('not-found', 'Retailer not found.');
    const retailer = retailerSnap.val();
    if (asNumber(retailer.totalCollected) + diff < 0) {
      throw new HttpsError('failed-precondition', 'Retailer collected total would become invalid.');
    }

    updates[`retailers/${retailerId}/totalCollected`] = admin.database.ServerValue.increment(diff);
    updates[`retailers/${retailerId}/lastUpdatedAt`] = nowIso;
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
  } else if (type === 'DISTRIBUTE_VFCASH') {
    const retailerId = tx.toId ? tx.toId.toString() : '';
    if (!retailerId) {
      throw new HttpsError('failed-precondition', 'Distribution transaction is missing retailer.');
    }
    const retailerSnap = await db.ref(`retailers/${retailerId}`).once('value');
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
    Object.assign(updates, await removeGeneratedTransaction(`DIST-${transactionId.substring(0, 8)}`));
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
    if (!retailerId) throw new HttpsError('failed-precondition', 'Credit return transaction is missing retailer.');
    const retailerSnap = await db.ref(`retailers/${retailerId}`).once('value');
    if (!retailerSnap.exists()) throw new HttpsError('not-found', 'Retailer not found.');
    if (asNumber(retailerSnap.val().totalCollected) < amount) {
      throw new HttpsError('failed-precondition', 'Retailer collected total is too low to reverse this credit return.');
    }
    updates[`retailers/${retailerId}/totalCollected`] = admin.database.ServerValue.increment(-amount);
    updates[`retailers/${retailerId}/lastUpdatedAt`] = nowIso;
    Object.assign(updates, await removeGeneratedTransaction(`CRTN-${transactionId.substring(0, 8)}`));
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





