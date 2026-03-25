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

async function getCallerRole(uid) {
  const snap = await admin.database().ref(`users/${uid}`).once('value');
  const user = snap.val();
  return user?.role || null;
}

exports.collectRetailerCash = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Login required');
  }

  const role = await getCallerRole(uid);
  if (!role || !['ADMIN', 'FINANCE', 'COLLECTOR'].includes(role)) {
    throw new HttpsError('permission-denied', 'Unauthorized');
  }

  const collectorId = request.data?.collectorId?.toString();
  const retailerId = request.data?.retailerId?.toString();
  const amount = asNumber(request.data?.amount);
  const createdByUid = uid;
  const notes = request.data?.notes?.toString().trim() || null;

  if (!collectorId || !retailerId || amount <= 0) {
    throw new HttpsError('invalid-argument', 'Invalid collection request.');
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

  const pendingDebt = asNumber(retailer.totalAssigned) - asNumber(retailer.totalCollected);
  const addedToCollected = pendingDebt > 0 ? Math.min(amount, pendingDebt) : 0;
  const addedToCredit = amount - addedToCollected;
  let appliedNotes = notes;
  if (addedToCredit > 0) {
    const creditNote = `(+${addedToCredit.toFixed(0)} EGP added to Credit)`;
    appliedNotes = appliedNotes ? `${appliedNotes} ${creditNote}` : creditNote;
  }

  const txId = uuidv4();
  const nowIso = new Date().toISOString();
  await db.ref().update({
    [`financial_ledger/${txId}`]: {
      id: txId,
      type: 'COLLECT_CASH',
      amount,
      collectedPortion: addedToCollected,
      creditPortion: addedToCredit,
      fromId: retailerId,
      fromLabel: retailer.name || 'Retailer',
      toId: collectorId,
      toLabel: collector.name || 'Collector',
      createdByUid,
      notes: appliedNotes,
      timestamp: Date.now(),
    },
    [`collectors/${collectorId}/cashOnHand`]: admin.database.ServerValue.increment(amount),
    [`collectors/${collectorId}/totalCollected`]: admin.database.ServerValue.increment(amount),
    [`collectors/${collectorId}/lastUpdatedAt`]: nowIso,
    [`retailers/${retailerId}/lastUpdatedAt`]: nowIso,
    ...(addedToCollected > 0
      ? { [`retailers/${retailerId}/totalCollected`]: admin.database.ServerValue.increment(addedToCollected) }
      : {}),
    ...(addedToCredit > 0
      ? { [`retailers/${retailerId}/credit`]: admin.database.ServerValue.increment(addedToCredit) }
      : {}),
  });

  return { txId, addedToCollected, addedToCredit };
});

exports.depositCollectorCash = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Login required');
  }

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
    const cashOnHand = asNumber(current);
    if (cashOnHand < amount) {
      return;
    }
    return cashOnHand - amount;
  });

  if (!cashResult.committed) {
    throw new HttpsError('failed-precondition', 'Collector does not have enough cash on hand.');
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
    await db.ref(`collectors/${collectorId}/cashOnHand`).transaction((current) => asNumber(current) + amount);
    throw new HttpsError('internal', error.message || 'Unable to complete deposit.');
  }

  return { txId };
});


