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
const PAGE_SIZE = 30;
const REGION = 'asia-east1';
const SYNC_LOCK_PATH = 'system/locks/bybit_sync';
const SYNC_LOCK_TTL_MS = 9 * 60 * 1000;

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
      status: 50,
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

    const lastItemTs = parseInt(items[items.length - 1].createDate || items[items.length - 1].createTime || 0);
    if (beginTime && lastItemTs < beginTime) break;

    page++;
    if (page > 20) break;
  }

  // Client-side date filter — reliable regardless of Bybit sort order.
  // Use >= so orders created exactly at beginTime are NOT dropped.
  const filtered = beginTime
    ? allOrders.filter(o => parseInt(o.createDate || o.createTime || 0) >= beginTime)
    : allOrders;

  filtered.sort((a, b) => parseInt(a.createDate || a.createTime || 0) - parseInt(b.createDate || b.createTime || 0));
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
  const body = { orderId, currentPage: '1', size: '30' };
  const jsonBody = JSON.stringify(body);
  const headers = getBybitHeaders(apiKey, apiSecret, jsonBody);

  try {
    const res = await axios.post(`${BYBIT_BASE_URL}/v5/p2p/order/message/listpage`, jsonBody, { headers });
    const data = res.data;
    if ((data.retCode ?? data.ret_code) !== 0) return [];

    const result = data.result;
    if (Array.isArray(result)) return result;
    if (result && Array.isArray(result.result)) return result.result;
    if (result && Array.isArray(result.list)) return result.list;
    if (result && Array.isArray(result.items)) return result.items;
    return [];
  } catch (e) {
    return [];
  }
}

function extractPaymentMethodName(json) {
  let pmName = 'Unknown';
  let acc = '';

  if (json.confirmedPayTerm) {
    if (json.confirmedPayTerm.paymentConfigVo && json.confirmedPayTerm.paymentConfigVo.paymentName) {
      pmName = json.confirmedPayTerm.paymentConfigVo.paymentName;
    }
    acc = json.confirmedPayTerm.accountNo || json.confirmedPayTerm.mobile || '';
    if (acc) pmName = `${pmName} (${acc})`;
  }

  if (pmName === 'Unknown' || pmName === 'Unknown ()') {
    pmName = json.paymentName || json.paymentMethodName || json.paymentMethod || 'Unknown';
    // Sometimes paymentMethod is an integer in simplifyList but a string in order/info, handle safely
    if (typeof pmName === 'number') pmName = pmName.toString();
  }

  if ((pmName === 'Unknown' || pmName === 'Unknown ()') && Array.isArray(json.paymentTermList) && json.paymentTermList.length > 0) {
    const first = json.paymentTermList[0];
    if (first && first.paymentConfigVo && first.paymentConfigVo.paymentName) {
      pmName = first.paymentConfigVo.paymentName;
    }
    acc = (first && (first.accountNo || first.mobile)) || '';
    if (acc) pmName = `${pmName} (${acc})`;
  }

  return pmName === 'Unknown ()' ? 'Unknown' : pmName;
}

// ── Core Sync Logic ─────────────────────────────────────────────────────

function buildSyncLock(ownerId) {
  const now = Date.now();
  return {
    ownerId,
    acquiredAt: now,
    expiresAt: now + SYNC_LOCK_TTL_MS,
  };
}

async function acquireSyncLock(db, ownerId) {
  const lockRef = db.ref(SYNC_LOCK_PATH);
  const now = Date.now();
  const result = await lockRef.transaction((current) => {
    const expiresAt = Number(current && current.expiresAt ? current.expiresAt : 0);
    if (!current || expiresAt <= now || current.ownerId === ownerId) {
      return buildSyncLock(ownerId);
    }
    return;
  });

  if (result.committed) {
    console.log(`[Lock] Acquired by ${ownerId}. Expires at: ${new Date(result.snapshot.val().expiresAt).toISOString()}`);
  } else {
    const current = result.snapshot.val();
    console.log(`[Lock] Acquisition failed for ${ownerId}. Currently held by ${current?.ownerId} until ${current ? new Date(current.expiresAt).toISOString() : 'unknown'}`);
  }

  return result.committed ? result.snapshot.val() : null;
}

async function releaseSyncLock(db, ownerId) {
  const lockRef = db.ref(SYNC_LOCK_PATH);
  const result = await lockRef.transaction((current) => {
    if (current && current.ownerId === ownerId) {
      return null;
    }
    return;
  });

  if (result.committed) {
    console.log(`[Lock] Released by ${ownerId}`);
  } else {
    const current = result.snapshot.val();
    console.log(`[Lock] Release failed for ${ownerId}. Lock was ${current ? 'held by ' + current.ownerId : 'already empty'}`);
  }
}

async function processSync(ignoreEnabledFlag = false, beginTimeOverride = null) {
  console.log(`[Sync] Starting sync cycle (Manual: ${ignoreEnabledFlag})`);
  const db = admin.database();

  const configSnap = await db.ref('system/sync_config/enabled').once('value');
  if (!ignoreEnabledFlag && configSnap.val() !== true) {
    console.log('[Sync] Skipped: Globally disabled in system/sync_config/enabled.');
    return { skippedByConfig: true };
  }

  const lockOwnerId = `${ignoreEnabledFlag ? 'manual' : 'scheduled'}_${uuidv4()}`;
  const lock = await acquireSyncLock(db, lockOwnerId);
  if (!lock) {
    console.log('[Sync] Skipped: another sync invocation already holds the lock.');
    return { added: 0, skipped: 0, skippedByLock: true };
  }

  try {
    const [credsSnap, numbersSnap, syncSnap, banksSnap] = await Promise.all([
      db.ref('system/api_credentials/bybit').once('value'),
      db.ref('mobile_numbers').once('value'),
      db.ref('sync_data').once('value'),
      db.ref('bank_accounts').once('value'),
    ]);

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
    let beginTime;
    if (beginTimeOverride != null) {
      beginTime = beginTimeOverride;
      console.log(`[Sync] Using override beginTime: ${new Date(beginTime).toISOString()} (TS: ${beginTime})`);
    } else {
      // Extended lookback window (24h) to catch orders that complete late.
      // Efficiency is maintained via optimized deduplication below.
      const lookbackMs = 24 * 60 * 60 * 1000;
      beginTime = lastSyncedOrderTs > 0 ? (lastSyncedOrderTs - lookbackMs) : (Date.now() - lookbackMs);

      // Limit lookback to 48h to prevent excessive pagination on stale markers
      const minBeginTime = Date.now() - (48 * 60 * 60 * 1000);
      if (beginTime < minBeginTime) beginTime = minBeginTime;
    }

    console.log(`[Sync] Fetching orders created after: ${new Date(beginTime).toISOString()} (TS: ${beginTime})`);

    const orders = await fetchAllOrdersSince(apiKey, apiSecret, beginTime);
    console.log(`[Sync] Bybit returned ${orders.length} potential new orders.`);

    // Faster deduplication: only check IDs present in the current Bybit batch.
    // This avoids pre-loading thousands of historic IDs.
    const existingLedgerIds = new Set();
    const existingTxIds = new Set();

    if (orders.length > 0) {
      const checkStartTime = Date.now();
      const checkPromises = orders.map(async (order) => {
        const orderId = order.id || order.orderId;
        const [lSnap, tSnap] = await Promise.all([
          db.ref('financial_ledger').orderByChild('bybitOrderId').equalTo(orderId).limitToFirst(1).once('value'),
          db.ref('transactions').orderByChild('bybitOrderId').equalTo(orderId).limitToFirst(1).once('value')
        ]);
        if (lSnap.exists()) existingLedgerIds.add(orderId);
        if (tSnap.exists()) existingTxIds.add(orderId);
      });
      await Promise.all(checkPromises);
      console.log(`[Sync] Deduplication check for ${orders.length} orders took ${Date.now() - checkStartTime}ms.`);
    }
    console.log(`[Sync] Found ${existingLedgerIds.size} already in ledger and ${existingTxIds.size} already in transactions for dedup.`);

    let added = 0;
    let skipped = 0;
    let newLastSyncedTs = lastSyncedOrderTs;
    const numbersToRecalculate = new Set();

    for (const order of orders) {
      const orderTs = parseInt(order.createTime || order.createDate || 0);
      const orderId = order.id || order.orderId;

      if (existingLedgerIds.has(orderId)) {
        skipped++;
        continue;
      }

      const details = await fetchOrderDetails(apiKey, apiSecret, orderId) || order;
      const chatMsgs = await fetchChatMessages(apiKey, apiSecret, orderId);
      const chatSummary = chatMsgs.map((m) => `${m.nickName}: ${m.message || m.content}`).join('\n');

      const paymentMethodString = extractPaymentMethodName(details);

      let matchedPhone = findMatchedPhone(chatSummary, knownNumbers);
      if (!matchedPhone) {
        matchedPhone = findMatchedPhone(paymentMethodString, knownNumbers);
      }
      if (!matchedPhone) {
        const orderPmString = extractPaymentMethodName(order);
        matchedPhone = findMatchedPhone(orderPmString, knownNumbers);
      }

      let matchedPhoneId = matchedPhone ? phoneToId[matchedPhone] : null;
      if (!matchedPhoneId && parseInt(details.side) === 1 && numbersSnap.exists()) {
        const numbers = Object.entries(numbersSnap.val());
        const defaultNum = numbers.find(([id, n]) => n.isDefault);
        if (defaultNum) {
          matchedPhoneId = defaultNum[0];
          matchedPhone = defaultNum[1].phoneNumber;
        }
      }

      const side = parseInt(details.side);
      const amount = parseFloat(details.amount);
      const price = parseFloat(details.price);
      const quantity = parseFloat(details.quantity);
      const currency = details.currencyId || 'EGP';
      const timestamp = new Date(orderTs).toISOString();

      const updates = {};
      const txId = uuidv4();
      const ledgerId = uuidv4();

      let fromId = null;
      let fromLabel = side === 0 ? 'Bank' : 'USD Exchange';
      if (side === 0) {
        const isVodafoneCash = paymentMethodString.toLowerCase().includes('vodafone');

        if (isVodafoneCash) {
          let targetId = matchedPhoneId;
          let targetPhone = matchedPhone;

          if (!targetId && numbersSnap.exists()) {
            const numbers = Object.entries(numbersSnap.val());
            const defaultNum = numbers.find(([id, n]) => n.isDefault);
            if (defaultNum) {
              targetId = defaultNum[0];
              targetPhone = defaultNum[1].phoneNumber;
            }
          }

          if (targetId && targetPhone) {
            fromId = targetId;
            fromLabel = targetPhone;
            matchedPhoneId = targetId;
            matchedPhone = targetPhone;

            const now = Date.now();
            const d = new Date(now);
            const todayStart = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
            const monthStart = new Date(d.getFullYear(), d.getMonth(), 1).getTime();

            updates[`mobile_numbers/${matchedPhoneId}/outTotalUsed`] = admin.database.ServerValue.increment(amount);
            if (orderTs >= todayStart) {
              updates[`mobile_numbers/${matchedPhoneId}/outDailyUsed`] = admin.database.ServerValue.increment(amount);
            }
            if (orderTs >= monthStart) {
              updates[`mobile_numbers/${matchedPhoneId}/outMonthlyUsed`] = admin.database.ServerValue.increment(amount);
            }
            updates[`mobile_numbers/${matchedPhoneId}/lastUpdatedAt`] = new Date().toISOString();
          } else {
            fromId = null;
            fromLabel = 'Vodafone Cash (Unassigned)';
          }
        } else {
          const banks = banksSnap.val();
          if (banks) {
            const defaultBank = Object.values(banks).find((b) => b.isDefaultForBuy);
            if (defaultBank) {
              fromId = defaultBank.id;
              fromLabel = defaultBank.bankName;
              updates[`bank_accounts/${defaultBank.id}/balance`] = admin.database.ServerValue.increment(-amount);
            }
          }
        }
      }

      if (!existingTxIds.has(orderId)) {
        updates[`transactions/${txId}`] = {
          id: txId,
          phoneNumber: matchedPhone || null,
          amount,
          currency,
          timestamp,
          bybitOrderId: orderId,
          status: 'completed',
          paymentMethod: paymentMethodString === 'Unknown' ? 'Bybit P2P' : paymentMethodString,
          side,
          chatHistory: chatSummary,
          price,
          quantity,
          token: details.tokenId || 'USDT',
        };
      }

      updates[`financial_ledger/${ledgerId}`] = {
        id: ledgerId,
        type: side === 0 ? 'BUY_USDT' : 'SELL_USDT',
        amount,
        usdtPrice: price,
        usdtQuantity: quantity,
        fromId,
        fromLabel,
        toLabel: side === 0 ? 'USD Exchange' : (matchedPhone || 'Vodafone Cash'),
        toId: side === 1 ? matchedPhoneId : null,
        bybitOrderId: orderId,
        createdByUid: 'server_sync',
        timestamp: orderTs,
      };

      if (side === 0) {
        updates['usd_exchange/usdtBalance'] = admin.database.ServerValue.increment(quantity);
      } else {
        updates['usd_exchange/usdtBalance'] = admin.database.ServerValue.increment(-quantity);
        if (matchedPhoneId) {
          const now = Date.now();
          const d = new Date(now);
          const todayStart = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
          const monthStart = new Date(d.getFullYear(), d.getMonth(), 1).getTime();
          updates[`mobile_numbers/${matchedPhoneId}/inTotalUsed`] = admin.database.ServerValue.increment(amount);
          if (orderTs >= todayStart) {
            updates[`mobile_numbers/${matchedPhoneId}/inDailyUsed`] = admin.database.ServerValue.increment(amount);
          }
          if (orderTs >= monthStart) {
            updates[`mobile_numbers/${matchedPhoneId}/inMonthlyUsed`] = admin.database.ServerValue.increment(amount);
          }
          updates[`mobile_numbers/${matchedPhoneId}/lastUpdatedAt`] = new Date().toISOString();
        }
      }
      updates['usd_exchange/lastPrice'] = price;
      updates['usd_exchange/lastUpdatedAt'] = new Date().toISOString();

      await db.ref().update(updates);

      existingLedgerIds.add(orderId);
      existingTxIds.add(orderId);
      if (orderTs > newLastSyncedTs) newLastSyncedTs = orderTs;

      if (matchedPhone) numbersToRecalculate.add(matchedPhone);
      added++;
    }

    const safeNewMarker = Math.max(newLastSyncedTs, beginTime);
    if (safeNewMarker < lastSyncedOrderTs) {
      console.error(`[Sync] CRITICAL: Marker would move backward! Safe: ${safeNewMarker}, Old: ${lastSyncedOrderTs}. Keeping old.`);
    }

    await db.ref('sync_data').update({
      lastSyncedOrderTs: Math.max(safeNewMarker, lastSyncedOrderTs),
      lastSyncTime: Date.now(),
      lastServerSyncStatus: `Success: Added ${added}, Skipped ${skipped} at ${new Date().toISOString()}`,
    });

    console.log(`[Sync] Finished. Added: ${added}, Skipped: ${skipped}, New Marker: ${Math.max(safeNewMarker, lastSyncedOrderTs)}`);

    // Sequential recalculation is disabled to prevent timeouts.
    // Sync already uses ServerValue.increment() for real-time accuracy.
    if (numbersToRecalculate.size > 0) {
      console.log(`[Sync] Incremental usage updated for ${numbersToRecalculate.size} phones. Full recalculation skipped to save time.`);
    }

    return { added, skipped };
  } finally {
    try {
      await releaseSyncLock(db, lockOwnerId);
    } catch (e) {
      console.error('[Sync] Failed to release sync lock:', e);
    }
  }
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
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime();

  let inDailyUsed = 0, outDailyUsed = 0;
  let inMonthlyUsed = 0, outMonthlyUsed = 0;
  let inTotalUsed = 0, outTotalUsed = 0;

  if (txSnap.exists()) {
    Object.values(txSnap.val()).forEach(tx => {
      if (tx.status !== 'completed') return;

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
  schedule: 'every 1 minutes',
  region: REGION,
  timeoutSeconds: 300,
}, async (event) => {
  return await processSync(false);
});

exports.manualSyncBybit = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const userSnap = await admin.database().ref(`users/${uid}`).once('value');
  const user = userSnap.val();
  if (!user || (user.role !== 'ADMIN' && user.role !== 'FINANCE')) {
    throw new HttpsError('permission-denied', 'Unauthorized');
  }
  const beginTimeOverride = request.data?.beginTime ? parseInt(request.data.beginTime) : null;
  return await processSync(true, beginTimeOverride);
});
