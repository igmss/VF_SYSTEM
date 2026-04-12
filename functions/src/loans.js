const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { v4: uuidv4 } = require('uuid');
const { asNumber, requireFinanceRole } = require('./shared/helpers');

const REGION = 'asia-east1';

exports.issueLoan = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const { sourceType, sourceId, borrowerName, borrowerPhone, amount, notes, createdByUid } = request.data;
  const numAmount = asNumber(amount);

  if (!sourceType || !sourceId || !borrowerName || numAmount <= 0) {
    throw new HttpsError('invalid-argument', 'Invalid loan issuance request.');
  }

  const db = admin.database();
  const now = new Date();
  const nowIso = now.toISOString();
  const nowTs = now.getTime();
  const loanId = uuidv4();
  const txId = uuidv4();

  let sourceLabel = 'Source';
  const updates = {};

  if (sourceType === 'bank') {
    const bankRef = db.ref(`bank_accounts/${sourceId}`);
    const bankSnap = await bankRef.once('value');
    if (!bankSnap.exists()) throw new HttpsError('not-found', 'Bank account not found.');
    const bank = bankSnap.val();
    sourceLabel = bank.bankName || 'Bank Account';

    const balanceResult = await bankRef.child('balance').transaction((current) => {
      if (current === null) return current;
      const balance = asNumber(current);
      if (balance < numAmount) return; // Abort
      return balance - numAmount;
    });

    if (!balanceResult.committed) {
      throw new HttpsError('failed-precondition', 'Insufficient bank balance.');
    }
  } else if (sourceType === 'collector') {
    const collectorRef = db.ref(`collectors/${sourceId}`);
    const collectorSnap = await collectorRef.once('value');
    if (!collectorSnap.exists()) throw new HttpsError('not-found', 'Collector not found.');
    const collector = collectorSnap.val();
    sourceLabel = collector.name || 'Collector';

    const balanceResult = await collectorRef.child('cashOnHand').transaction((current) => {
      if (current === null) return current;
      const balance = asNumber(current);
      if (balance < numAmount) return; // Abort
      return balance - numAmount;
    });

    if (!balanceResult.committed) {
      throw new HttpsError('failed-precondition', 'Insufficient collector cash.');
    }
  } else {
    throw new HttpsError('invalid-argument', 'Invalid source type.');
  }

  updates[`loans/${loanId}`] = {
    id: loanId,
    borrowerName,
    borrowerPhone: borrowerPhone || '',
    principalAmount: numAmount,
    amountRepaid: 0,
    sourceType,
    sourceId,
    sourceLabel,
    status: 'active',
    issuedAt: nowTs,
    lastUpdatedAt: nowTs,
    notes: notes || null,
    createdByUid: createdByUid || uid,
  };

  updates[`financial_ledger/${txId}`] = {
    id: txId,
    type: 'LOAN_ISSUED',
    amount: numAmount,
    fromId: sourceId,
    fromLabel: sourceLabel,
    toLabel: borrowerName,
    notes: `Loan issued to ${borrowerName}${notes ? ': ' + notes : ''}`,
    createdByUid: createdByUid || uid,
    timestamp: nowTs,
  };

  try {
    await db.ref().update(updates);
    return { success: true, loanId, txId };
  } catch (error) {
    // Rollback balance
    if (sourceType === 'bank') {
      await db.ref(`bank_accounts/${sourceId}/balance`).transaction((c) => asNumber(c) + numAmount).catch(() => {});
    } else {
      await db.ref(`collectors/${sourceId}/cashOnHand`).transaction((c) => asNumber(c) + numAmount).catch(() => {});
    }
    throw new HttpsError('internal', 'Failed to save loan record. Balance rolled back.');
  }
});

exports.recordLoanRepayment = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const { loanId, amount, createdByUid } = request.data;
  const numAmount = asNumber(amount);

  if (!loanId || numAmount <= 0) {
    throw new HttpsError('invalid-argument', 'Invalid repayment request.');
  }

  const db = admin.database();
  const loanRef = db.ref(`loans/${loanId}`);
  const loanSnap = await loanRef.once('value');
  if (!loanSnap.exists()) throw new HttpsError('not-found', 'Loan record not found.');
  const loan = loanSnap.val();

  const outstanding = asNumber(loan.principalAmount) - asNumber(loan.amountRepaid);
  if (numAmount > outstanding + 0.01) {
    throw new HttpsError('failed-precondition', `Repayment exceeds outstanding balance (${outstanding.toFixed(2)} EGP).`);
  }

  const now = new Date();
  const nowTs = now.getTime();
  const txId = uuidv4();
  const updates = {};

  const newAmountRepaid = asNumber(loan.amountRepaid) + numAmount;
  const newStatus = newAmountRepaid >= asNumber(loan.principalAmount) - 0.01 ? 'fully_repaid' : 'active';

  updates[`loans/${loanId}/amountRepaid`] = newAmountRepaid;
  updates[`loans/${loanId}/status`] = newStatus;
  updates[`loans/${loanId}/lastUpdatedAt`] = nowTs;

  updates[`financial_ledger/${txId}`] = {
    id: txId,
    type: 'LOAN_REPAYMENT',
    amount: numAmount,
    fromLabel: loan.borrowerName,
    toId: loan.sourceId,
    toLabel: loan.sourceLabel,
    notes: `Repayment from ${loan.borrowerName}${newStatus === 'fully_repaid' ? ' (Fully Repaid)' : ''}`,
    createdByUid: createdByUid || uid,
    timestamp: nowTs,
  };

  if (loan.sourceType === 'bank') {
    updates[`bank_accounts/${loan.sourceId}/balance`] = admin.database.ServerValue.increment(numAmount);
    updates[`bank_accounts/${loan.sourceId}/lastUpdatedAt`] = now.toISOString();
  } else if (loan.sourceType === 'collector') {
    updates[`collectors/${loan.sourceId}/cashOnHand`] = admin.database.ServerValue.increment(numAmount);
    updates[`collectors/${loan.sourceId}/lastUpdatedAt`] = now.toISOString();
  }

  try {
    await db.ref().update(updates);
    return { success: true, txId, status: newStatus };
  } catch (error) {
    throw new HttpsError('internal', error.message || 'Unable to complete repayment.');
  }
});

exports.recordExpense = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const { sourceId, amount, category, notes, createdByUid } = request.data;
  const numAmount = asNumber(amount);

  if (!sourceId || numAmount <= 0) {
    throw new HttpsError('invalid-argument', 'sourceId and a positive amount are required.');
  }

  const db = admin.database();
  const now = new Date();
  const nowTs = now.getTime();
  const txId = uuidv4();

  // ── Validate bank account and atomically deduct balance ───────────────────
  const bankRef = db.ref(`bank_accounts/${sourceId}`);
  const bankSnap = await bankRef.once('value');
  if (!bankSnap.exists()) throw new HttpsError('not-found', 'Bank account not found.');
  const sourceLabel = bankSnap.val().bankName || 'Bank Account';

  const result = await bankRef.child('balance').transaction((current) => {
    if (current === null) return current;
    const balance = asNumber(current);
    if (balance < numAmount) return; // Abort — insufficient funds
    return balance - numAmount;
  });

  if (!result.committed) {
    throw new HttpsError('failed-precondition', 'Insufficient bank balance to record expense.');
  }

  // ── Write the ledger entry ─────────────────────────────────────────────────
  await db.ref(`financial_ledger/${txId}`).set({
    id: txId,
    type: 'EXPENSE_BANK',
    amount: numAmount,
    fromId: sourceId,
    fromLabel: sourceLabel,
    notes: notes || (category ? `Category: ${category}` : null),
    category: category || null,
    createdByUid: createdByUid || uid,
    timestamp: nowTs,
  });

  return { success: true, txId };
});
