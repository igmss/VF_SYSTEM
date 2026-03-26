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

function getRetailerPendingDebt(retailer) {
  const pending = asNumber(retailer.totalAssigned) - asNumber(retailer.totalCollected);
  return pending > 0 ? pending : 0;
}

async function getCallerRole(uid) {
  const snap = await admin.database().ref(`users/${uid}`).once('value');
  const user = snap.val();
  return user?.role || null;
}

// ─────────────────────────────────────────────────────────────────────────────
// collectRetailerCash
//
// Design:
//   Phase 1 – Read retailer + collector data, compute split (no writes).
//   Phase 2 – Single atomic multi-path db.update():
//               • Ledger entry
//               • Retailer totalCollected / credit  (via ServerValue.increment)
//               • Collector cashOnHand / totalCollected (via ServerValue.increment)
//
// No transaction needed for the retailer path because:
//   • totalCollected and credit only grow upward during collection.
//   • We compute the exact split from the snapshot taken 1-2 ms ago.
//   • ServerValue.increment is individually atomic per path.
//   • A race where another collection fires simultaneously is extremely
//     unlikely in this domain and does not cause data corruption — worst case
//     is `totalCollected` slightly exceeds `totalAssigned` (credit would
//     absorb the overshoot), which the existing credit logic already handles.
// ─────────────────────────────────────────────────────────────────────────────
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
  const createdByUid = uid;
  const notes = request.data?.notes?.toString().trim() || null;

  if (!collectorId || !retailerId || amount <= 0) {
    throw new HttpsError('invalid-argument', 'Invalid collection request.');
  }

  const db = admin.database();

  // ─── Phase 1: Read, validate, compute split ───────────────────────────────
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

  const pendingDebt = getRetailerPendingDebt(retailer);
  const addedToCollected = pendingDebt > 0 ? Math.min(amount, pendingDebt) : 0;
  const addedToCredit = amount - addedToCollected;

  // ─── Phase 2: Atomic multi-path write ────────────────────────────────────
  const txId = uuidv4();
  const nowIso = new Date().toISOString();

  let appliedNotes = notes;
  if (addedToCredit > 0) {
    const creditNote = `(+${addedToCredit.toFixed(0)} EGP added to Credit)`;
    appliedNotes = appliedNotes ? `${appliedNotes} ${creditNote}` : creditNote;
  }

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
    [`retailers/${retailerId}/totalCollected`]: admin.database.ServerValue.increment(addedToCollected),
    [`retailers/${retailerId}/credit`]: admin.database.ServerValue.increment(addedToCredit),
    [`retailers/${retailerId}/lastUpdatedAt`]: nowIso,
    [`collectors/${collectorId}/cashOnHand`]: admin.database.ServerValue.increment(amount),
    [`collectors/${collectorId}/totalCollected`]: admin.database.ServerValue.increment(amount),
    [`collectors/${collectorId}/lastUpdatedAt`]: nowIso,
  });

  return { txId, addedToCollected, addedToCredit };
});

// ─────────────────────────────────────────────────────────────────────────────
// depositCollectorCash
//
// Design:
//   Phase 1 – Read both documents, validate collector has enough cashOnHand.
//   Phase 2 – Transaction on cashOnHand only (balance check + debit, atomic).
//   Phase 3 – Single atomic multi-path db.update():
//               • Ledger entry
//               • Collector totalDeposited  (ServerValue.increment)
//               • Bank balance              (ServerValue.increment)
//             On failure → rollback cashOnHand via another transaction.
//
// We need a transaction on cashOnHand (not just a read + write) because two
// concurrent deposits from the same collector simultaneously must not both
// pass the balance check against the same stale snapshot.
// ─────────────────────────────────────────────────────────────────────────────
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

  // ─── Phase 1: Read & validate ─────────────────────────────────────────────
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

  // ─── Phase 2: Atomically debit cashOnHand ─────────────────────────────────
  // Using a transaction ensures two simultaneous deposits cannot both pass
  // the balance check against stale data.
  const cashResult = await db.ref(`collectors/${collectorId}/cashOnHand`).transaction((current) => {
    if (current === null) return current; // Let Firebase retry with real value

    const cashOnHand = asNumber(current);
    if ((amount - cashOnHand) > 0.01) {
      return; // Explicit abort: genuinely insufficient cash on hand
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

  // ─── Phase 3: Atomic multi-path write ────────────────────────────────────
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
    // Roll back the cashOnHand debit — the ledger/bank write was never applied.
    await db.ref(`collectors/${collectorId}/cashOnHand`).transaction((current) => {
      return asNumber(current) + amount;
    }).catch(() => {});
    throw new HttpsError('internal', error.message || 'Unable to complete deposit.');
  }

  return { txId };
});
