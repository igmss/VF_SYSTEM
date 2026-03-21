const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const axios = require('axios');
const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const BYBIT_BASE_URL = 'https://api.bybit.com';
const PAGE_SIZE = 50;
const REGION = 'asia-east1';

let timeOffsetMs = 0;

// ── Helpers ─────────────────────────────────────────────────────────────

async function syncServerTime() {
    try {
        const res = await axios.get(`${BYBIT_BASE_URL}/v5/market/time`);
        if (res.data && res.data.result && res.data.result.timeNano) {
            const serverMs = Math.floor(parseInt(res.data.result.timeNano) / 1000000);
            timeOffsetMs = serverMs - Date.now();
            console.log(`[Sync] Synced server time. Offset: ${timeOffsetMs}ms`);
        }
    } catch (e) {
        console.error(`[Sync] Failed to sync server time: ${e.message}`);
    }
}

function generateSignature(secret, payload) {
  return crypto.createHmac('sha256', secret).update(payload).digest('hex');
}

function getBybitHeaders(apiKey, apiSecret, jsonBody) {
  const ts = (Date.now() + timeOffsetMs).toString();
  const recvWindow = '30000';
  const payload = ts + apiKey + recvWindow + jsonBody;
  const sig = generateSignature(apiSecret, payload);

  return {
    'X-BAPI-API-KEY': apiKey,
    'X-BAPI-TIMESTAMP': ts,
    'X-BAPI-SIGN': sig,
    'X-BAPI-RECV-WINDOW': recvWindow,
    'Content-Type': 'application/json',
  };
}

function normalizePhone(n) {
  if (!n) return '';
  const digits = n.replace(/\D/g, '');
  if (digits.startsWith('20')) return '0' + digits.substring(2);
  return digits;
}

function findMatchedPhone(text, knownNumbers) {
  if (!text || !knownNumbers || knownNumbers.length === 0) return null;
  const regex = /(01[0125][\d\s-]{8,15})/g;
  const matches = text.match(regex);
  if (!matches) return null;

  const found = matches.map(m => normalizePhone(m)).filter(m => m.length === 11);
  const normalizedKnown = knownNumbers.map(n => normalizePhone(n));

  for (let i = 0; i < normalizedKnown.length; i++) {
    const idx = found.indexOf(normalizedKnown[i]);
    if (idx !== -1) return knownNumbers[i];
  }
  return null;
}

// ── Bybit API Wrappers ──────────────────────────────────────────────────

async function fetchAllOrdersSince(apiKey, apiSecret, beginTime) {
  let allOrders = [];
  let page = 1;

  while (true) {
    const body = {
      page: page,
      size: PAGE_SIZE,
      status: '50',
      beginTime: beginTime ? beginTime.toString() : undefined,
    };

    const jsonBody = JSON.stringify(body);
    const headers = getBybitHeaders(apiKey, apiSecret, jsonBody);

    const res = await axios.post(`${BYBIT_BASE_URL}/v5/p2p/order/simplifyList`, jsonBody, { headers });

    const data = res.data;
    const retCode = data.retCode ?? data.ret_code ?? -1;
    const retMsg = data.retMsg ?? data.ret_msg ?? 'Unknown error';

    if (retCode !== 0) {
      console.error(`[Sync] Bybit API Error: ${retMsg}`, data);
      throw new Error(`Bybit API Error (simplifyList): ${retMsg}`);
    }

    const items = data.result.items || data.result.list || [];
    if (items.length === 0) break;

    allOrders = allOrders.concat(items);
    if (items.length < PAGE_SIZE) break;

    const lastItemTs = parseInt(items[items.length - 1].createTime || 0);
    if (beginTime && lastItemTs < beginTime) break;

    page++;
    if (page > 20) break;
  }

  const filtered = beginTime
    ? allOrders.filter(o => parseInt(o.createTime || 0) >= beginTime)
    : allOrders;

  filtered.sort((a, b) => parseInt(a.createTime || 0) - parseInt(b.createTime || 0));
  return filtered;
}

async function fetchOrderDetails(apiKey, apiSecret, orderId) {
  const body = { orderId };
  const jsonBody = JSON.stringify(body);
  const headers = getBybitHeaders(apiKey, apiSecret, jsonBody);

  try {
    const res = await axios.post(`${BYBIT_BASE_URL}/v5/p2p/order/info`, jsonBody, { headers });
    const data = res.data;
    if ((data.retCode ?? data.ret_code) !== 0) return null;
    return data.result;
  } catch (e) {
    return null;
  }
}

async function fetchChatMessages(apiKey, apiSecret, orderId) {
  const body = { orderId, currentPage: '1', size: '50' };
  const jsonBody = JSON.stringify(body);
  const headers = getBybitHeaders(apiKey, apiSecret, jsonBody);

  try {
    const res = await axios.post(`${BYBIT_BASE_URL}/v5/p2p/order/message/listpage`, jsonBody, { headers });
    const data = res.data;
    if ((data.retCode ?? data.ret_code) !== 0) return [];

    const result = data.result;
    if (Array.isArray(result)) return result;
    if (result && Array.isArray(result.result)) return result.result;
    return [];
  } catch (e) {
    return [];
  }
}

// ── Core Sync Logic ─────────────────────────────────────────────────────

async function processSync(ignoreEnabledFlag = false) {
  console.log(`[Sync] Starting sync cycle (Manual: ${ignoreEnabledFlag})`);
  const db = admin.database();

  const [credsSnap, numbersSnap, syncSnap, banksSnap, configSnap] = await Promise.all([
    db.ref('system/api_credentials/bybit').once('value'),
    db.ref('mobile_numbers').once('value'),
    db.ref('sync_data').once('value'),
    db.ref('bank_accounts').once('value'),
    db.ref('system/sync_config/enabled').once('value'),
  ]);

  if (!ignoreEnabledFlag && configSnap.val() !== true) {
    console.log('[Sync] Skipped: Globally disabled in system/sync_config/enabled.');
    return { skippedByConfig: true };
  }

  if (!credsSnap.exists()) {
    console.error('[Sync] Error: Missing Bybit API credentials in database.');
    return { error: 'Missing credentials' };
  }

  await syncServerTime();

  const { apiKey, apiSecret } = credsSnap.val();
  const knownNumbers = [];
  const phoneToId = {};
  if (numbersSnap.exists()) {
    Object.entries(numbersSnap.val()).forEach(([id, n]) => {
      knownNumbers.push(n.phoneNumber);
      phoneToId[n.phoneNumber] = id;
    });
  }

  const lastSyncedOrderTs = syncSnap.child('lastSyncedOrderTs').val() || 0;
  const beginTime = lastSyncedOrderTs > 0 ? lastSyncedOrderTs + 1 : Date.now() - (24 * 60 * 60 * 1000);

  console.log(`[Sync] Fetching orders created after: ${new Date(beginTime).toISOString()} (TS: ${beginTime})`);

  const orders = await fetchAllOrdersSince(apiKey, apiSecret, beginTime);
  console.log(`[Sync] Bybit returned ${orders.length} potential new orders.`);

  let added = 0;
  let skipped = 0;
  let newLastSyncedTs = lastSyncedOrderTs;
  const numbersToRecalculate = new Set();

  for (const order of orders) {
    const orderTs = parseInt(order.createTime || order.createDate || 0);
    const orderId = order.id || order.orderId;

    if (orderTs > newLastSyncedTs) newLastSyncedTs = orderTs;

    const [txDup, ledgerDup] = await Promise.all([
      db.ref('transactions').orderByChild('bybitOrderId').equalTo(orderId).once('value'),
      db.ref('financial_ledger').orderByChild('bybitOrderId').equalTo(orderId).once('value')
    ]);

    if (txDup.exists() || ledgerDup.exists()) {
      skipped++;
      continue;
    }

    const details = await fetchOrderDetails(apiKey, apiSecret, orderId) || order;
    const chatMsgs = await fetchChatMessages(apiKey, apiSecret, orderId);
    const chatSummary = chatMsgs.map(m => `${m.nickName}: ${m.message || m.content}`).join('\n');

    let matchedPhone = findMatchedPhone(chatSummary, knownNumbers);
    if (!matchedPhone) {
      let pmName = '';
      if (details.confirmedPayTerm && details.confirmedPayTerm.paymentConfigVo) {
        pmName = details.confirmedPayTerm.paymentConfigVo.paymentName || '';
        const acc = details.confirmedPayTerm.accountNo || details.confirmedPayTerm.mobile || '';
        if (acc) pmName += ` (${acc})`;
      }
      matchedPhone = findMatchedPhone(pmName, knownNumbers);
    }
    const matchedPhoneId = matchedPhone ? phoneToId[matchedPhone] : null;

    const side = parseInt(details.side);
    const amount = parseFloat(details.amount);
    const price = parseFloat(details.price);
    const quantity = parseFloat(details.quantity);
    const currency = details.currencyId || 'EGP';
    const timestamp = new Date(orderTs).toISOString();

    const updates = {};
    const txId = uuidv4();
    const ledgerId = uuidv4();

    updates[`transactions/${txId}`] = {
      id: txId,
      phoneNumber: matchedPhone || null,
      amount, currency, timestamp,
      bybitOrderId: orderId,
      status: 'completed',
      paymentMethod: details.paymentMethodName || details.paymentMethod || 'Bybit P2P',
      side, chatHistory: chatSummary,
      price, quantity, token: details.tokenId || 'USDT'
    };

    updates[`financial_ledger/${ledgerId}`] = {
      id: ledgerId,
      type: side === 0 ? 'BUY_USDT' : 'SELL_USDT',
      amount, usdtPrice: price, usdtQuantity: quantity,
      fromLabel: side === 0 ? 'Bank' : 'USD Exchange',
      toLabel: side === 0 ? 'USD Exchange' : (matchedPhone || 'Vodafone Cash'),
      toId: side === 1 ? matchedPhoneId : null,
      bybitOrderId: orderId,
      createdByUid: 'server_sync',
      timestamp: orderTs
    };

    if (side === 0) {
      const banks = banksSnap.val();
      if (banks) {
        const defaultBank = Object.values(banks).find(b => b.isDefaultForBuy);
        if (defaultBank) {
          updates[`bank_accounts/${defaultBank.id}/balance`] = admin.database.ServerValue.increment(-amount);
          updates[`financial_ledger/${ledgerId}/fromId`] = defaultBank.id;
          updates[`financial_ledger/${ledgerId}/fromLabel`] = defaultBank.bankName;
        }
      }
      updates['usd_exchange/usdtBalance'] = admin.database.ServerValue.increment(quantity);
    } else {
      updates['usd_exchange/usdtBalance'] = admin.database.ServerValue.increment(-quantity);
    }
    updates['usd_exchange/lastPrice'] = price;
    updates['usd_exchange/lastUpdatedAt'] = new Date().toISOString();

    await db.ref().update(updates);
    if (matchedPhone) numbersToRecalculate.add(matchedPhone);
    added++;
  }

  await db.ref('sync_data').update({
    lastSyncedOrderTs: newLastSyncedTs,
    lastSyncTime: Date.now(),
    lastServerSyncStatus: `Success: Added ${added}, Skipped ${skipped} at ${new Date().toISOString()}`
  });

  console.log(`[Sync] Finished. Added: ${added}, Skipped: ${skipped}, New Marker: ${newLastSyncedTs}`);

  for (const phone of numbersToRecalculate) {
    try {
        await recalculateUsage(phone);
    } catch (e) {
        console.error(`Failed to recalculate usage for ${phone}:`, e);
    }
  }

  return { added, skipped };
}

async function recalculateUsage(phoneNumber) {
    const db = admin.database();
    const [numSnap, txSnap] = await Promise.all([
        db.ref('mobile_numbers').orderByChild('phoneNumber').equalTo(phoneNumber).once('value'),
        db.ref('transactions').orderByChild('phoneNumber').equalTo(phoneNumber).once('value')
    ]);

    if (!numSnap.exists()) return;
    const numberKey = Object.keys(numSnap.val())[0];
    const number = numSnap.val()[numberKey];

    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const monthStart = new Date(now.getFullYear(), now.month(), 1).getTime();

    let inDailyUsed = 0, outDailyUsed = 0;
    let inMonthlyUsed = 0, outMonthlyUsed = 0;
    let inTotalUsed = 0, outTotalUsed = 0;

    if (txSnap.exists()) {
        Object.values(txSnap.val()).forEach(tx => {
            if (tx.status !== 'completed') return;
            const pm = (tx.paymentMethod || '').toLowerCase();
            if (!pm.includes('voda') && !pm.includes('vf')) return;

            const txTs = new Date(tx.timestamp).getTime();
            const amount = parseFloat(tx.amount);
            const isIncoming = tx.side === 1;

            if (isIncoming) inTotalUsed += amount; else outTotalUsed += amount;
            if (txTs >= todayStart) {
                if (isIncoming) inDailyUsed += amount; else outDailyUsed += amount;
            }
            if (txTs >= monthStart) {
                if (isIncoming) inMonthlyUsed += amount; else outMonthlyUsed += amount;
            }
        });
    }

    await db.ref(`mobile_numbers/${numberKey}`).update({
        inDailyUsed, outDailyUsed,
        inMonthlyUsed, outMonthlyUsed,
        inTotalUsed, outTotalUsed,
        lastUpdatedAt: new Date().toISOString()
    });
}

// ── Cloud Functions ─────────────────────────────────────────────────────

exports.resetDailyLimits = onSchedule({
  schedule: '1 0 * * *',
  timeZone: 'Africa/Cairo',
  region: REGION,
}, async (event) => {
  const db = admin.database();
  const snapshot = await db.ref('mobile_numbers').once('value');
  if (!snapshot.exists()) return;
  const updates = {};
  Object.keys(snapshot.val()).forEach(id => {
    updates[`mobile_numbers/${id}/inDailyUsed`] = 0;
    updates[`mobile_numbers/${id}/outDailyUsed`] = 0;
  });
  await db.ref().update(updates);
});

exports.syncBybitOrders = onSchedule({
  schedule: '*/2 * * * *',
  region: REGION,
  timeoutSeconds: 300,
}, async (event) => {
  await processSync(false);
});

exports.manualSyncBybit = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const userSnap = await admin.database().ref(`users/${uid}`).once('value');
  const user = userSnap.val();
  if (!user || (user.role !== 'ADMIN' && user.role !== 'FINANCE')) {
      throw new HttpsError('permission-denied', 'Unauthorized');
  }
  return await processSync(true);
});
