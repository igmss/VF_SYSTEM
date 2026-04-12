const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { v4: uuidv4 } = require('uuid');
const { asNumber, requireFinanceRole } = require('./shared/helpers');

const REGION = 'asia-east1';

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
    if (current === null) return current; // Signal Firebase to fetch data

    const next = asNumber(current) - amount;
    if (next < 0) return; // Abort: truly insufficient
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
    await bankRef.child('balance').transaction((current) => {
      if (current === null) return current;
      return asNumber(current) + amount;
    }).catch(() => {});
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
