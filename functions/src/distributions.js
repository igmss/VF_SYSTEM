const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { v4: uuidv4 } = require('uuid');
const {
  asNumber,
  requireFinanceRole,
  getMobileNumberBalance,
  updateMobileNumberUsageTransaction,
  computeDistributionAmounts,
  applyMobileNumberUsageDelta,
} = require('./shared/helpers');

const REGION = 'asia-east1';

exports.distributeVfCash = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  console.log(`--- [distributeVfCash] REQUEST: UID=${uid} ---`);
  console.log(`    DATA:`, JSON.stringify(request.data));

  const retailerId = request.data?.retailerId?.toString();
  const fromVfNumberId = request.data?.fromVfNumberId?.toString();
  const fromVfPhone = request.data?.fromVfPhone?.toString();
  const amount = asNumber(request.data?.amount);
  const fees = asNumber(request.data?.fees);
  const chargeFeesToRetailer = request.data?.chargeFeesToRetailer === true;
  const applyCredit = request.data?.applyCredit === true;
  const createdByUid = uid;
  const notes = request.data?.notes?.toString().trim() || null;

  if (!retailerId) throw new HttpsError('invalid-argument', 'Missing "retailerId" field.');
  if (!fromVfNumberId) throw new HttpsError('invalid-argument', 'Missing "fromVfNumberId" field.');
  if (!fromVfPhone) throw new HttpsError('invalid-argument', 'Missing "fromVfPhone" field.');
  if (amount <= 0) throw new HttpsError('invalid-argument', 'The "amount" must be greater than zero.');
  if (fees < 0) throw new HttpsError('invalid-argument', 'The "fees" cannot be negative.');

  const db = admin.database();
  const totalDeduction = amount + fees;
  const now = new Date();
  const nowIso = now.toISOString();
  const dateStr = nowIso.split('T')[0];
  const nowTs = now.getTime();

  // ─── Phase 1: Compute retailer amounts (read-only, no lock) ──────────────
  const { retailer, actualDebtIncrease, creditUsed } = await computeDistributionAmounts({
    db, retailerId, amount, fees, chargeFeesToRetailer, applyCredit,
  });

  // ─── Phase 2: Atomically reserve VF number balance via transaction ────────
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

  // ─── Phase 3: Build and commit the full atomic multi-path write ───────────
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
    [`retailers/${retailerId}/totalAssigned`]: admin.database.ServerValue.increment(actualDebtIncrease),
    [`retailers/${retailerId}/lastUpdatedAt`]: nowIso,
    [`summary/daily_flow/${dateStr}/vf`]: admin.database.ServerValue.increment(amount),
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

exports.distributeInstaPay = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const retailerId = request.data?.retailerId?.toString();
  const bankAccountId = request.data?.bankAccountId?.toString();
  const amount = asNumber(request.data?.amount);
  const fees = asNumber(request.data?.fees);
  const applyCredit = request.data?.applyCredit === true;
  const createdByUid = uid;
  const notes = request.data?.notes?.toString().trim() || null;

  const db = admin.database();
  const dbUrl = admin.app().options.databaseURL;
  console.log(`--- [distributeInstaPay] Started by UID: ${uid} ---`);
  console.log(`    DB_INSTANCE: ${dbUrl}`);
  console.log(`    RETAILER_ID: "${retailerId}"`);
  console.log(`    BANK_ID: "${bankAccountId}"`);
  console.log(`    AMT: ${amount}, FEES: ${fees}, CREDIT: ${applyCredit}`);

  if (!retailerId) throw new HttpsError('invalid-argument', 'Missing "retailerId" field.');
  if (!bankAccountId) throw new HttpsError('invalid-argument', 'Missing "bankAccountId" field.');
  if (amount <= 0) throw new HttpsError('invalid-argument', 'The "amount" must be greater than zero.');

  const now = new Date();
  const nowIso = now.toISOString();
  const dateStr = nowIso.split('T')[0];
  const nowTs = now.getTime();

  // ─── Phase 1: Fetching retailer and bank ────────────
  console.log(`    Phase 1: Fetching paths...`);
  const [retailerSnap, bankSnap] = await Promise.all([
    db.ref(`retailers/${retailerId}`).once('value'),
    db.ref(`bank_accounts/${bankAccountId}`).once('value')
  ]);

  if (!retailerSnap.exists()) {
    console.error(`    ABORT: Path "retailers/${retailerId}" NOT FOUND.`);
    throw new HttpsError('not-found', 'Retailer not found.');
  }
  const retailer = retailerSnap.val();
  console.log(`    RETAILER_NAME: "${retailer.name}"`);

  if (!bankSnap.exists()) {
    console.error(`    ABORT: Path "bank_accounts/${bankAccountId}" NOT FOUND.`);
    throw new HttpsError('not-found', 'Bank account not found.');
  }
  const bank = bankSnap.val();
  console.log(`    BANK_SNAP_VAL:`, JSON.stringify(bank));
  console.log(`    BANK_BALANCE_KEY_VAL:`, bank.balance);

  const profitPer1000 = asNumber(retailer.instaPayProfitPer1000);
  const profitAmount = (amount / 1000.0) * profitPer1000;
  let actualDebtIncrease = Math.ceil(amount + profitAmount);
  let creditUsed = 0.0;

  const currentCredit = asNumber(retailer.credit);
  if (applyCredit && currentCredit > 0) {
    creditUsed = Math.min(currentCredit, actualDebtIncrease);
    actualDebtIncrease -= creditUsed;
  }

  console.log(`    Calculated: Profit: ${profitAmount}, Debt Increase: ${actualDebtIncrease}, Credit Used: ${creditUsed}`);

  // ─── Phase 2: Atomically deduct from bank balance ───
  console.log(`    Phase 2: Transaction on Path: "bank_accounts/${bankAccountId}/balance"`);
  const bankRef = db.ref(`bank_accounts/${bankAccountId}`);
  const totalDeduction = amount + fees;

  const balanceResult = await bankRef.child('balance').transaction((current) => {
    if (current === null) {
      console.log(`    TX_RUN: current is null, retrying once firebase fetches data...`);
      return current;
    }

    const balance = asNumber(current);
    console.log(`    TX_RUN: current_parsed=${balance}, need=${totalDeduction}`);

    if ((totalDeduction - balance) > 0.01) {
      console.log(`    TX_ABORT: balance (${balance}) < need (${totalDeduction})`);
      return; // Abort
    }
    const next = Math.max(0, balance - totalDeduction);
    console.log(`    TX_COMMIT: next_val=${next}`);
    return next;
  });

  if (!balanceResult.committed) {
    console.error(`    ABORT: Transaction failed. Snapshot value:`, balanceResult.snapshot.val());
    throw new HttpsError(
      'failed-precondition',
      `Insufficient bank balance. Available: ${asNumber(balanceResult.snapshot.val()).toFixed(2)} EGP.`
    );
  }
  console.log(`    Bank balance deducted successfully. New: ${balanceResult.snapshot.val()}`);

  // ─── Phase 3: Commited multi-path write ─────────────
  console.log(`    Phase 3: Building updates...`);
  const txId = uuidv4();
  const profitTxId = uuidv4();
  const feeTxId = uuidv4();
  const bankLabel = bank.bankName || 'Bank Account';
  const retailerName = retailer.name || 'Retailer';

  const creditNotes = creditUsed > 0 ? `, -${creditUsed} Credit Used` : '';
  const feesLabel = fees > 0 ? `, Fee: ${fees} EGP` : '';
  const appliedNotes = notes && notes.length > 0
    ? `${notes} (Rate: ${profitPer1000}/1K${feesLabel}, Debt +${actualDebtIncrease} EGP${creditNotes})`
    : `Rate: ${profitPer1000}/1K${feesLabel}, Debt +${actualDebtIncrease} EGP${creditNotes}`;

  const updates = {
    [`financial_ledger/${txId}`]: {
      id: txId,
      type: 'DISTRIBUTE_INSTAPAY',
      amount,
      fromId: bankAccountId,
      fromLabel: bankLabel,
      toId: retailerId,
      toLabel: retailerName,
      createdByUid,
      notes: appliedNotes,
      timestamp: nowTs,
    },
    [`retailers/${retailerId}/instaPayTotalAssigned`]: admin.database.ServerValue.increment(actualDebtIncrease),
    [`retailers/${retailerId}/lastUpdatedAt`]: nowIso,
    [`bank_accounts/${bankAccountId}/lastUpdatedAt`]: nowIso,
    [`summary/daily_flow/${dateStr}/insta`]: admin.database.ServerValue.increment(amount),
  };

  if (creditUsed > 0) {
    updates[`retailers/${retailerId}/credit`] = admin.database.ServerValue.increment(-creditUsed);
  }

  if (profitAmount > 0) {
    updates[`financial_ledger/${profitTxId}`] = {
      id: profitTxId,
      type: 'INSTAPAY_DIST_PROFIT',
      amount: profitAmount,
      toId: retailerId,
      toLabel: retailerName,
      createdByUid,
      relatedLedgerId: txId,
      notes: `InstaPay Profit for distribution of ${amount} EGP to ${retailerName}`,
      timestamp: nowTs,
    };
  }

  if (fees > 0) {
    updates[`financial_ledger/${feeTxId}`] = {
      id: feeTxId,
      type: 'EXPENSE_INSTAPAY_FEE',
      amount: fees,
      fromId: bankAccountId,
      fromLabel: bankLabel,
      createdByUid,
      relatedLedgerId: txId,
      notes: `InstaPay transfer fee for distribution of ${amount} EGP to ${retailerName}`,
      timestamp: nowTs,
    };
  }

  try {
    await db.ref().update(updates);
    console.log(`--- [distributeInstapay] SUCCESS committed. ---`);
  } catch (error) {
    console.error(`--- [distributeInstapay] FINAL_ERROR:`, error);
    // Roll back bank balance reservation
    await bankRef.child('balance').transaction((current) => {
      if (current === null) return current;
      return asNumber(current) + totalDeduction;
    }).catch(() => {});
    throw new HttpsError('internal', error.message || 'Unable to complete InstaPay distribution.');
  }

  return { txId, actualDebtIncrease, profitAmount, fees };
});

exports.transferInternalVfCash = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const { fromVfId, toVfId, amount, fees, notes } = request.data;
  const numAmount = asNumber(amount);
  const numFees = asNumber(fees);

  if (!fromVfId || !toVfId || fromVfId === toVfId || numAmount <= 0 || numFees < 0) {
    throw new HttpsError('invalid-argument', 'Invalid internal transfer request.');
  }

  const db = admin.database();
  const now = new Date();
  const nowIso = now.toISOString();
  const nowTs = now.getTime();

  const totalDeduction = numAmount + numFees;
  const vfReservation = await updateMobileNumberUsageTransaction({
    numberId: fromVfId,
    amountDelta: totalDeduction,
    direction: 'outgoing',
    timestampMs: nowTs,
    nowIso,
    requireSufficientBalance: true,
  });

  if (!vfReservation.committed) {
    throw new HttpsError('failed-precondition', 'Insufficient Vodafone balance in the source number.');
  }

  const sourceNumber = vfReservation.snapshot.val() || {};
  const sourceVfPhone = sourceNumber.phoneNumber || fromVfId;

  const destSnap = await db.ref(`mobile_numbers/${toVfId}`).once('value');
  if (!destSnap.exists()) {
    // Rollback if destination doesn't exist
    await updateMobileNumberUsageTransaction({
      numberId: fromVfId,
      amountDelta: -totalDeduction,
      direction: 'incoming',
      timestampMs: nowTs,
      nowIso,
      requireSufficientBalance: false,
    });
    throw new HttpsError('not-found', 'Destination Vodafone number not found.');
  }

  const destNumber = destSnap.val();
  const destVfPhone = destNumber.phoneNumber || toVfId;

  const updates = {};
  applyMobileNumberUsageDelta(updates, {
    numberId: toVfId,
    amountDelta: numAmount,
    direction: 'incoming',
    timestampMs: nowTs,
    nowIso,
  });

  const txId = uuidv4();
  const cashTxIdDest = uuidv4();
  const cashTxIdSource = uuidv4();

  updates[`financial_ledger/${txId}`] = {
    id: txId,
    type: 'INTERNAL_VF_TRANSFER',
    amount: numAmount,
    fromId: fromVfId,
    fromLabel: sourceVfPhone,
    toId: toVfId,
    toLabel: destVfPhone,
    createdByUid: uid,
    notes: notes || `Internal Transfer from ${sourceVfPhone} to ${destVfPhone}`,
    timestamp: nowTs,
  };

  updates[`transactions/${cashTxIdSource}`] = {
    id: cashTxIdSource,
    phoneNumber: sourceVfPhone,
    amount: totalDeduction,
    currency: 'EGP',
    timestamp: nowIso,
    bybitOrderId: `INT-${txId.substring(0, 8)}`,
    status: 'completed',
    paymentMethod: 'Internal VF Transfer (Out)',
    side: 0,
    relatedLedgerId: txId,
    chatHistory: `Sent to ${destVfPhone} (Amount: ${numAmount}, Fee: ${numFees})`,
  };

  updates[`transactions/${cashTxIdDest}`] = {
    id: cashTxIdDest,
    phoneNumber: destVfPhone,
    amount: numAmount,
    currency: 'EGP',
    timestamp: nowIso,
    bybitOrderId: `INT-${txId.substring(0, 8)}`,
    status: 'completed',
    paymentMethod: 'Internal VF Transfer (In)',
    side: 1,
    relatedLedgerId: txId,
    chatHistory: `Received from ${sourceVfPhone}`,
  };

  if (numFees > 0) {
    const feeTxId = uuidv4();
    updates[`financial_ledger/${feeTxId}`] = {
      id: feeTxId,
      type: 'INTERNAL_VF_TRANSFER_FEE',
      amount: numFees,
      fromId: fromVfId,
      fromLabel: sourceVfPhone,
      toId: toVfId,
      toLabel: destVfPhone,
      createdByUid: uid,
      relatedLedgerId: txId,
      notes: 'Transfer Fee',
      timestamp: nowTs,
    };
  }

  try {
    await db.ref().update(updates);
    return { success: true, txId };
  } catch (error) {
    // Rollback source if write fails
    await updateMobileNumberUsageTransaction({
      numberId: fromVfId,
      amountDelta: -totalDeduction,
      direction: 'incoming',
      timestampMs: nowTs,
      nowIso,
      requireSufficientBalance: false,
    });
    throw new HttpsError('internal', 'Internal transfer failed. Rolled back VF source.');
  }
});
