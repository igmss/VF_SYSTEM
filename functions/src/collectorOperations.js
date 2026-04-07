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

function roundCurrency(value) {
  return Number(asNumber(value).toFixed(2));
}

function getRetailerPendingDebt(retailer) {
  const pending = asNumber(retailer.totalAssigned) - asNumber(retailer.totalCollected);
  return pending > 0 ? pending : 0;
}

function getRetailerInstaPayPendingDebt(retailer) {
  const pending = asNumber(retailer.instaPayTotalAssigned) - asNumber(retailer.instaPayTotalCollected);
  return pending > 0 ? pending : 0;
}

async function getCallerRole(uid) {
  const snap = await admin.database().ref(`users/${uid}`).once('value');
  const user = snap.val();
  return user?.role || null;
}

exports.collectRetailerCash = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');

  const role = await getCallerRole(uid);
  if (!role || !['ADMIN', 'FINANCE', 'COLLECTOR'].includes(role)) {
    throw new HttpsError('permission-denied', 'Unauthorized');
  }

  const collectorId = request.data?.collectorId?.toString();
  const retailerId = request.data?.retailerId?.toString();
  const amount = asNumber(request.data?.amount);
  let vfAmount = asNumber(request.data?.vfAmount);
  let instaPayAmount = asNumber(request.data?.instaPayAmount);
  const createdByUid = uid;
  const notes = request.data?.notes?.toString().trim() || null;

  if (!collectorId || !retailerId || amount <= 0) {
    throw new HttpsError('invalid-argument', 'Invalid collection request.');
  }

  // Backward compatibility: If no specific amounts provided, treat total amount as VF portion
  if (vfAmount === 0 && instaPayAmount === 0) {
    vfAmount = amount;
  }

  // Validate that the sum of portions matches the total amount
  if (Math.abs((vfAmount + instaPayAmount) - amount) > 0.01) {
    throw new HttpsError('invalid-argument', 'The sum of VF and InstaPay portions must match the total amount.');
  }

  const db = admin.database();
  const [collectorSnap, retailerSnap] = await Promise.all([
    db.ref(`collectors/${collectorId}`).once('value'),
    db.ref(`retailers/${retailerId}`).once('value'),
  ]);

  if (!collectorSnap.exists() || !retailerSnap.exists()) {
    throw new HttpsError('not-found', 'Collector or retailer not found.');
  }

  const collector = collectorSnap.val();
  const retailer = retailerSnap.val();

  if (role === 'COLLECTOR') {
    if (collector.uid !== uid || retailer.assignedCollectorId !== uid) {
      throw new HttpsError('permission-denied', 'Collector is not allowed to collect for this retailer.');
    }
  }

  // ─── Phase 1: Handle VF Channel Collection ──────────────
  const pendingDebt = getRetailerPendingDebt(retailer);
  if (vfAmount > pendingDebt + 0.01) {
    throw new HttpsError('failed-precondition', `VF amount ${vfAmount} exceeds VF pending debt ${pendingDebt.toFixed(2)}.`);
  }
  const addedToCollected = pendingDebt > 0 ? Math.min(vfAmount, pendingDebt) : 0;
  const addedToCredit = vfAmount - addedToCollected;

  // ─── Phase 2: Handle InstaPay Channel Collection ──────────────
  const instaPayPendingDebt = getRetailerInstaPayPendingDebt(retailer);
  if (instaPayAmount > instaPayPendingDebt + 0.01) {
    throw new HttpsError('failed-precondition', `InstaPay amount ${instaPayAmount} exceeds InstaPay pending debt ${instaPayPendingDebt.toFixed(2)}.`);
  }

  const txId = uuidv4();
  const instaTxId = uuidv4();
  const nowIso = new Date().toISOString();

  const updates = {
    [`retailers/${retailerId}/lastUpdatedAt`]: nowIso,
    [`collectors/${collectorId}/cashOnHand`]: admin.database.ServerValue.increment(amount),
    [`collectors/${collectorId}/totalCollected`]: admin.database.ServerValue.increment(amount),
    [`collectors/${collectorId}/lastUpdatedAt`]: nowIso,
  };

  // VF Ledger & Retailer update
  if (vfAmount > 0) {
    let appliedNotes = notes;
    if (addedToCredit > 0) {
      const creditNote = `(+${addedToCredit.toFixed(0)} EGP added to Credit)`;
      appliedNotes = appliedNotes ? `${appliedNotes} ${creditNote}` : creditNote;
    }

    updates[`financial_ledger/${txId}`] = {
      id: txId,
      type: 'COLLECT_CASH',
      amount: vfAmount,
      collectedPortion: addedToCollected,
      creditPortion: addedToCredit,
      fromId: retailerId,
      fromLabel: retailer.name || 'Retailer',
      toId: collectorId,
      toLabel: collector.name || 'Collector',
      createdByUid,
      notes: appliedNotes,
      timestamp: Date.now(),
    };
    if (addedToCollected > 0) {
      updates[`retailers/${retailerId}/totalCollected`] = admin.database.ServerValue.increment(addedToCollected);
    }
    if (addedToCredit > 0) {
      updates[`retailers/${retailerId}/credit`] = admin.database.ServerValue.increment(addedToCredit);
    }
  }

  // InstaPay Ledger & Retailer update
  if (instaPayAmount > 0) {
    updates[`financial_ledger/${instaTxId}`] = {
      id: instaTxId,
      type: 'COLLECT_INSTAPAY_CASH',
      amount: instaPayAmount,
      fromId: retailerId,
      fromLabel: retailer.name || 'Retailer',
      toId: collectorId,
      toLabel: collector.name || 'Collector',
      createdByUid,
      notes: notes,
      timestamp: Date.now(),
    };
    updates[`retailers/${retailerId}/instaPayTotalCollected`] = admin.database.ServerValue.increment(instaPayAmount);
  }

  await db.ref().update(updates);

  return { txId, instaTxId: instaPayAmount > 0 ? instaTxId : null, addedToCollected, addedToCredit };
});

exports.depositCollectorCash = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');

  const role = await getCallerRole(uid);
  if (!role || !['ADMIN', 'FINANCE', 'COLLECTOR'].includes(role)) {
    throw new HttpsError('permission-denied', 'Unauthorized');
  }

  const collectorId = request.data?.collectorId?.toString();
  const bankAccountId = request.data?.bankAccountId?.toString();
  const amount = asNumber(request.data?.amount);
  const createdByUid = uid;
  const notes = request.data?.notes?.toString().trim() || null;

  if (!collectorId || !bankAccountId || amount <= 0) {
    throw new HttpsError('invalid-argument', 'Invalid deposit request.');
  }

  const db = admin.database();
  const [collectorSnap, bankSnap] = await Promise.all([
    db.ref(`collectors/${collectorId}`).once('value'),
    db.ref(`bank_accounts/${bankAccountId}`).once('value'),
  ]);

  if (!collectorSnap.exists() || !bankSnap.exists()) {
    throw new HttpsError('not-found', 'Collector or bank account not found.');
  }

  const collector = collectorSnap.val();
  const bank = bankSnap.val();

  if (role === 'COLLECTOR' && collector.uid !== uid) {
    throw new HttpsError('permission-denied', 'Collector is not allowed to deposit for this account.');
  }

  const cashResult = await db.ref(`collectors/${collectorId}/cashOnHand`).transaction((current) => {
    if (current === null) return current;

    const cashOnHand = asNumber(current);
    if ((amount - cashOnHand) > 0.01) {
      return;
    }
    return Math.max(0, cashOnHand - amount);
  });

  if (!cashResult.committed) {
    const cashOnHand = asNumber(cashResult.snapshot?.val());
    throw new HttpsError(
      'failed-precondition',
      `Insufficient cash on hand. Available: ${cashOnHand.toFixed(2)} EGP, required: ${amount.toFixed(2)} EGP.`
    );
  }

  const txId = uuidv4();
  const nowIso = new Date().toISOString();

  try {
    await db.ref().update({
      [`financial_ledger/${txId}`]: {
        id: txId,
        type: 'DEPOSIT_TO_BANK',
        amount,
        fromId: collectorId,
        fromLabel: collector.name || 'Collector',
        toId: bankAccountId,
        toLabel: bank.bankName || 'Bank Account',
        createdByUid,
        notes,
        timestamp: Date.now(),
      },
      [`collectors/${collectorId}/totalDeposited`]: admin.database.ServerValue.increment(amount),
      [`collectors/${collectorId}/lastUpdatedAt`]: nowIso,
      [`bank_accounts/${bankAccountId}/balance`]: admin.database.ServerValue.increment(amount),
      [`bank_accounts/${bankAccountId}/lastUpdatedAt`]: nowIso,
    });
  } catch (error) {
    await db.ref(`collectors/${collectorId}/cashOnHand`).transaction((current) => {
      if (current === null) return current;
      return asNumber(current) + amount;
    }).catch(() => {});
    throw new HttpsError('internal', error.message || 'Unable to complete deposit.');
  }

  return { txId };
});

exports.depositCollectorCashToDefaultVf = onCall({ region: REGION }, async (request) => {
  // NOTE: Despite the legacy name, this function now accepts an explicit vfNumberId
  // chosen by the collector. Falls back to the isDefault flag if none provided.
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');

  const role = await getCallerRole(uid);
  if (!role || !['ADMIN', 'FINANCE', 'COLLECTOR'].includes(role)) {
    throw new HttpsError('permission-denied', 'Unauthorized');
  }

  const collectorId = request.data?.collectorId?.toString();
  const vfNumberIdParam = request.data?.vfNumberId?.toString() || null;
  const amount = asNumber(request.data?.amount);
  const createdByUid = uid;
  const notes = request.data?.notes?.toString().trim() || null;

  if (!collectorId || amount <= 0) {
    throw new HttpsError('invalid-argument', 'Invalid Vodafone deposit request.');
  }

  const db = admin.database();
  const [collectorSnap, vfNumbersSnap, settingsSnap] = await Promise.all([
    db.ref(`collectors/${collectorId}`).once('value'),
    db.ref('mobile_numbers').once('value'),
    db.ref('system/operation_settings').once('value'),
  ]);

  if (!collectorSnap.exists()) {
    throw new HttpsError('not-found', 'Collector not found.');
  }
  if (!vfNumbersSnap.exists() || typeof vfNumbersSnap.val() !== 'object') {
    throw new HttpsError('failed-precondition', 'No Vodafone numbers are configured.');
  }

  const collector = collectorSnap.val();
  if (role === 'COLLECTOR' && collector.uid !== uid) {
    throw new HttpsError('permission-denied', 'Collector is not allowed to deposit for this account.');
  }

  const vfEntries = Object.entries(vfNumbersSnap.val() || {}).filter(([, value]) => value && typeof value === 'object');
  if (vfEntries.length === 0) {
    throw new HttpsError('failed-precondition', 'No Vodafone numbers are configured.');
  }

  // Resolve the VF number: use explicit ID from client, or fall back to isDefault
  let rawVfNumberEntry;
  if (vfNumberIdParam) {
    rawVfNumberEntry = vfEntries.find(([id]) => id === vfNumberIdParam);
    if (!rawVfNumberEntry) {
      throw new HttpsError('not-found', `Vodafone number '${vfNumberIdParam}' not found.`);
    }
  } else {
    rawVfNumberEntry = vfEntries.find(([, value]) => value.isDefault === true);
    if (!rawVfNumberEntry) {
      throw new HttpsError('failed-precondition', 'No default Vodafone Cash number is set. Please select a VF number or ask admin to set a default.');
    }
  }
  const [vfNumberId, vfNumber] = rawVfNumberEntry;
  const vfPhone = vfNumber.phoneNumber || 'Default VF Number';
  const settings = settingsSnap.exists() && typeof settingsSnap.val() === 'object'
    ? settingsSnap.val()
    : {};
  const feeRatePer1000 = Math.max(0, settings.collectorVfDepositFeePer1000 == null ? 7.0 : asNumber(settings.collectorVfDepositFeePer1000));
  const feeProfit = roundCurrency((amount / 1000.0) * feeRatePer1000);
  const transferredAmount = roundCurrency(amount + feeProfit);

  const cashResult = await db.ref(`collectors/${collectorId}/cashOnHand`).transaction((current) => {
    if (current === null) return current;

    const cashOnHand = asNumber(current);
    if ((amount - cashOnHand) > 0.01) {
      return;
    }
    return Math.max(0, cashOnHand - amount);
  });

  if (!cashResult.committed) {
    const cashOnHand = asNumber(cashResult.snapshot?.val());
    throw new HttpsError(
      'failed-precondition',
      `Insufficient cash on hand. Available: ${cashOnHand.toFixed(2)} EGP, required: ${amount.toFixed(2)} EGP.`
    );
  }

  const txId = uuidv4();
  const profitTxId = uuidv4();
  const generatedTxId = uuidv4();
  const now = new Date();
  const nowIso = now.toISOString();
  const nowTs = now.getTime();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime();

  const detailNote =
    `Transferred ${transferredAmount.toFixed(2)} EGP to ${vfPhone} ` +
    `(cash ${amount.toFixed(2)} + profit ${feeProfit.toFixed(2)} @ ${feeRatePer1000.toFixed(2)}/1000)`;
  const appliedNotes = notes ? `${notes} (${detailNote})` : detailNote;

  const updates = {
    [`financial_ledger/${txId}`]: {
      id: txId,
      type: 'DEPOSIT_TO_VFCASH',
      amount,
      transferredAmount,
      feeAmount: feeProfit,
      feeRatePer1000,
      fromId: collectorId,
      fromLabel: collector.name || 'Collector',
      toId: vfNumberId,
      toLabel: vfPhone,
      createdByUid,
      notes: appliedNotes,
      generatedTransactionId: generatedTxId,
      timestamp: nowTs,
    },
    [`collectors/${collectorId}/totalDeposited`]: admin.database.ServerValue.increment(amount),
    [`collectors/${collectorId}/lastUpdatedAt`]: nowIso,
    [`transactions/${generatedTxId}`]: {
      id: generatedTxId,
      phoneNumber: vfPhone,
      amount: transferredAmount,
      currency: 'EGP',
      timestamp: nowIso,
      bybitOrderId: `CLDV-${txId.substring(0, 8)}`,
      status: 'completed',
      paymentMethod: 'Vodafone Collector Deposit',
      side: 1,
      relatedLedgerId: txId,
      chatHistory:
        `Collector deposit from ${collector.name || 'Collector'} ` +
        `(Cash: ${amount.toFixed(2)}, Profit: ${feeProfit.toFixed(2)})`,
    },
    // Record the full transferred amount (cash + profit) as incoming to the VF number.
    // This increases inTotalUsed which is used by getMobileNumberBalance to compute the current balance.
    [`mobile_numbers/${vfNumberId}/inTotalUsed`]: admin.database.ServerValue.increment(transferredAmount),
    [`mobile_numbers/${vfNumberId}/lastUpdatedAt`]: nowIso,
  };

  if (nowTs >= todayStart) {
    updates[`mobile_numbers/${vfNumberId}/inDailyUsed`] = admin.database.ServerValue.increment(transferredAmount);
  }
  if (nowTs >= monthStart) {
    updates[`mobile_numbers/${vfNumberId}/inMonthlyUsed`] = admin.database.ServerValue.increment(transferredAmount);
  }
  if (feeProfit > 0) {
    updates[`financial_ledger/${profitTxId}`] = {
      id: profitTxId,
      type: 'VFCASH_RETAIL_PROFIT',
      amount: feeProfit,
      fromId: collectorId,
      fromLabel: collector.name || 'Collector',
      toId: vfNumberId,
      toLabel: vfPhone,
      createdByUid,
      relatedLedgerId: txId,
      notes: 'Collector Vodafone deposit profit',
      timestamp: nowTs,
    };
  }

  try {
    await db.ref().update(updates);
  } catch (error) {
    await db.ref(`collectors/${collectorId}/cashOnHand`).transaction((current) => {
      if (current === null) return current;
      return asNumber(current) + amount;
    }).catch(() => {});
    throw new HttpsError('internal', error.message || 'Unable to complete Vodafone deposit.');
  }

  return {
    txId,
    vfNumberId,
    vfPhone,
    transferredAmount,
    feeAmount: feeProfit,
    feeRatePer1000,
  };
});