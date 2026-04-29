import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export const BYBIT_BASE_URL = 'https://api.bybit.com';
export const PAGE_SIZE = 30;
export const SYNC_LOCK_TTL_MS = 540000; // 9 minutes

let timeOffsetMs = 0;

// ── Pure Bybit Helpers ──────────────────────────────────────────────────

export function normalizePhone(n: string | null): string {
  if (!n) return '';
  const digits = n.replace(/\D/g, '');
  if (digits.startsWith('20')) return '0' + digits.substring(2);
  return digits;
}

export function findMatchedPhone(text: string | null, knownNumbers: string[]): string | null {
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

export function extractPaymentMethodName(json: any): string {
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

// ── Bybit API Wrappers ──────────────────────────────────────────────────

export async function syncServerTime(): Promise<void> {
  try {
    const res = await fetch(`${BYBIT_BASE_URL}/v5/market/time`);
    const data = await res.json();
    if (data && data.result && data.result.timeNano) {
      const serverMs = Math.floor(parseInt(data.result.timeNano) / 1000000);
      timeOffsetMs = serverMs - Date.now();
      console.log(`[Sync] Synced server time. Offset: ${timeOffsetMs}ms`);
    }
  } catch (e: any) {
    console.error(`[Sync] Failed to sync server time: ${e.message}`);
  }
}

async function generateSignature(secret: string, payload: string): Promise<string> {
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secret);
  const messageData = encoder.encode(payload);

  const key = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign("HMAC", key, messageData);
  return Array.from(new Uint8Array(signature))
    .map(b => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function getBybitHeaders(apiKey: string, apiSecret: string, jsonBody: string): Promise<Record<string, string>> {
  const ts = (Date.now() + timeOffsetMs).toString();
  const recvWindow = '30000';
  const payload = ts + apiKey + recvWindow + jsonBody;
  const sig = await generateSignature(apiSecret, payload);

  return {
    'X-BAPI-API-KEY': apiKey,
    'X-BAPI-TIMESTAMP': ts,
    'X-BAPI-SIGN': sig,
    'X-BAPI-RECV-WINDOW': recvWindow,
    'Content-Type': 'application/json',
  };
}

export async function fetchAllOrdersSince(apiKey: string, apiSecret: string, beginTime: number | null): Promise<any[]> {
  let allOrders: any[] = [];
  let page = 1;

  while (true) {
    const body: any = {
      page: page,
      size: PAGE_SIZE,
      status: '50',
      beginTime: beginTime ? beginTime.toString() : undefined,
    };

    const jsonBody = JSON.stringify(body);
    const headers = await getBybitHeaders(apiKey, apiSecret, jsonBody);

    const res = await fetch(`${BYBIT_BASE_URL}/v5/p2p/order/simplifyList`, {
      method: 'POST',
      headers,
      body: jsonBody
    });

    const data = await res.json();
    const retCode = data.retCode ?? data.ret_code ?? -1;
    const retMsg = data.retMsg ?? data.ret_msg ?? 'Unknown error';

    if (retCode !== 0) {
      console.error(`[Sync] Bybit API Error: ${retMsg} (Code: ${retCode})`, data);
      throw new Error(`Bybit API Error (simplifyList): ${retMsg}`);
    }
    
    console.log(`[Sync] Page ${page} fetched. Raw data keys: ${Object.keys(data.result || {})}`);

    const items = data.result.items || data.result.list || [];
    if (items.length === 0) break;

    allOrders = allOrders.concat(items);
    if (items.length < PAGE_SIZE) break;

    const lastItemTs = parseInt(items[items.length - 1].createDate || items[items.length - 1].createTime || 0);
    if (beginTime && lastItemTs < beginTime) break;

    page++;
    if (page > 20) break;
  }

  const filtered = beginTime
    ? allOrders.filter(o => parseInt(o.createDate || o.createTime || 0) >= beginTime)
    : allOrders;

  filtered.sort((a, b) => parseInt(a.createDate || a.createTime || 0) - parseInt(b.createDate || b.createTime || 0));
  return filtered;
}

export async function fetchOrderDetails(apiKey: string, apiSecret: string, orderId: string): Promise<any> {
  const body = { orderId };
  const jsonBody = JSON.stringify(body);
  const headers = await getBybitHeaders(apiKey, apiSecret, jsonBody);

  try {
    const res = await fetch(`${BYBIT_BASE_URL}/v5/p2p/order/info`, {
      method: 'POST',
      headers,
      body: jsonBody
    });
    const data = await res.json();
    if ((data.retCode ?? data.ret_code) !== 0) return null;
    return data.result;
  } catch (e) {
    return null;
  }
}

export async function fetchChatMessages(apiKey: string, apiSecret: string, orderId: string): Promise<any[]> {
  const body = { orderId, currentPage: '1', size: '30' };
  const jsonBody = JSON.stringify(body);
  const headers = await getBybitHeaders(apiKey, apiSecret, jsonBody);

  try {
    const res = await fetch(`${BYBIT_BASE_URL}/v5/p2p/order/message/listpage`, {
      method: 'POST',
      headers,
      body: jsonBody
    });
    const data = await res.json();
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

// ── Core Sync Logic ─────────────────────────────────────────────────────

export async function processSync(supabase: SupabaseClient, ignoreEnabledFlag: boolean, beginTimeOverride: number | null) {
  console.log(`[Sync] Starting sync cycle (Manual: ${ignoreEnabledFlag})`);

  // 1. Config check
  const { data: config } = await supabase
    .from('system_config')
    .select('value')
    .eq('key', 'sync_config')
    .single();

  const isEnabled = config?.value?.enabled === true;
  if (!isEnabled && !ignoreEnabledFlag) {
    console.log('[Sync] Skipped: Globally disabled in system_config.');
    return { skippedByConfig: true };
  }

  const lockId = `${ignoreEnabledFlag ? 'manual' : 'scheduled'}_${crypto.randomUUID()}`;
  
  // 2. Acquire lock
  const { data: lockResult } = await supabase.rpc('acquire_sync_lock', { 
    p_owner_id: lockId, 
    p_ttl_ms: SYNC_LOCK_TTL_MS 
  });

  if (!lockResult || lockResult[0]?.acquired !== true) {
    console.log('[Sync] Skipped: another sync invocation already holds the lock.');
    return { skippedByLock: true };
  }

  try {
    // 3. Parallel reads
    const [credsRes, numbersRes, syncRes, banksRes, exchangeRes] = await Promise.all([
      supabase.from('system_config').select('value').eq('key', 'bybit_metadata').single(),
      supabase.from('mobile_numbers').select('*'),
      supabase.from('sync_state').select('*').eq('id', 1).single(),
      supabase.from('bank_accounts').select('*'),
      supabase.from('usd_exchange').select('*').eq('id', 1).single()
    ]);

    if (!credsRes.data) {
      console.error('[Sync] Error: Missing Bybit API credentials (bybit_metadata) in database.');
      return { error: 'Missing credentials' };
    }

    const { apiKey, apiSecret } = credsRes.data.value;
    const knownNumbers: string[] = [];
    const phoneToId: Record<string, string> = {};
    if (numbersRes.data) {
      numbersRes.data.forEach(n => {
        knownNumbers.push(n.phone_number);
        phoneToId[n.phone_number] = n.id;
      });
    }

    const lastSyncedOrderTs = syncRes.data?.last_synced_order_ts || 0;
    const currentUsdtBalance = exchangeRes.data?.usdt_balance || 0;
    const defaultBank = banksRes.data?.find(b => b.is_default_for_buy);

    await syncServerTime();

    // 4. Compute beginTime
    let beginTime: number;
    if (beginTimeOverride != null) {
      beginTime = beginTimeOverride;
    } else {
      const lookbackMs = 24 * 60 * 60 * 1000;
      beginTime = lastSyncedOrderTs > 0 ? (lastSyncedOrderTs - lookbackMs) : (Date.now() - lookbackMs);
      const minBeginTime = Date.now() - (48 * 60 * 60 * 1000);
      if (beginTime < minBeginTime) beginTime = minBeginTime;
    }

    console.log(`[Sync] Fetching orders since: ${new Date(beginTime).toISOString()} (TS: ${beginTime}) using API Key: ${apiKey.substring(0, 4)}...`);

    // 5. Fetch orders
    const orders = await fetchAllOrdersSince(apiKey, apiSecret, beginTime);
    console.log(`[Sync] Bybit returned ${orders.length} potential new orders.`);

    // 6. Parallel dedup
    const existingLedgerIds = new Set<string>();
    const existingTxIds = new Set<string>();

    if (orders.length > 0) {
      const orderIds = orders.map(o => o.id || o.orderId);
      const [ledgerCheck, txCheck] = await Promise.all([
        supabase.from('financial_ledger').select('bybit_order_id').in('bybit_order_id', orderIds),
        supabase.from('transactions').select('bybit_order_id').in('bybit_order_id', orderIds)
      ]);
      ledgerCheck.data?.forEach(row => existingLedgerIds.add(row.bybit_order_id));
      txCheck.data?.forEach(row => existingTxIds.add(row.bybit_order_id));
    }

    let added = 0;
    let skipped = 0;
    let newLastSyncedTs = lastSyncedOrderTs;

    // 7. Per-order processing loop
    for (const order of orders) {
      const orderTs = parseInt(order.createTime || order.createDate || 0);
      const orderId = order.id || order.orderId;

      if (existingLedgerIds.has(orderId)) {
        skipped++;
        continue;
      }

      const details = await fetchOrderDetails(apiKey, apiSecret, orderId) || order;
      const chatMsgs = await fetchChatMessages(apiKey, apiSecret, orderId);
      const chatSummary = chatMsgs.map((m: any) => `${m.nickName}: ${m.message || m.content}`).join('\n');
      const paymentMethodString = extractPaymentMethodName(details);

      let matchedPhone = findMatchedPhone(chatSummary, knownNumbers) 
                         || findMatchedPhone(paymentMethodString, knownNumbers)
                         || findMatchedPhone(extractPaymentMethodName(order), knownNumbers);

      let matchedPhoneId = matchedPhone ? phoneToId[matchedPhone] : null;

      // Fallback for SELL (side 1) if no phone matched
      if (!matchedPhoneId && parseInt(details.side) === 1 && numbersRes.data) {
        const defaultNum = numbersRes.data.find(n => n.is_default);
        if (defaultNum) {
          matchedPhoneId = defaultNum.id;
          matchedPhone = defaultNum.phone_number;
        }
      }

      const side = parseInt(details.side);
      const amount = parseFloat(details.amount);
      const price = parseFloat(details.price);
      const quantity = parseFloat(details.quantity);
      const currency = details.currencyId || 'EGP';

      let fromId = null;
      let fromLabel = side === 0 ? 'Bank' : 'USD Exchange';
      let toId = side === 1 ? matchedPhoneId : null;
      let toLabel = side === 0 ? 'USD Exchange' : (matchedPhone || 'Vodafone Cash');

      let isVodafoneBuy = false;
      let bankId = null;

      if (side === 0) { // BUY
        isVodafoneBuy = paymentMethodString.toLowerCase().includes('vodafone');
        if (isVodafoneBuy) {
          if (!matchedPhoneId && numbersRes.data) {
            const defaultNum = numbersRes.data.find(n => n.is_default);
            if (defaultNum) {
              matchedPhoneId = defaultNum.id;
              matchedPhone = defaultNum.phone_number;
            }
          }
          if (matchedPhoneId) {
            fromId = matchedPhoneId;
            fromLabel = matchedPhone!;
          } else {
            fromLabel = 'Vodafone Cash (Unassigned)';
          }
        } else if (defaultBank) {
          fromId = defaultBank.id;
          fromLabel = defaultBank.bank_name;
          bankId = defaultBank.id;
        }
      }

      // 8. Execute atomic mutation via RPC
      const { error: rpcError } = await supabase.rpc('process_bybit_order_sync', {
        p_order_id: orderId,
        p_side: side,
        p_amount: amount,
        p_price: price,
        p_quantity: quantity,
        p_currency: currency,
        p_token: details.tokenId || 'USDT',
        p_timestamp_ms: orderTs,
        p_payment_method: paymentMethodString === 'Unknown' ? 'Bybit P2P' : paymentMethodString,
        p_chat_history: chatSummary,
        p_matched_phone: matchedPhone || null,
        p_matched_phone_id: matchedPhoneId,
        p_from_id: fromId,
        p_from_label: fromLabel,
        p_to_id: toId,
        p_to_label: toLabel,
        p_is_vodafone_buy: isVodafoneBuy,
        p_bank_id: bankId
      });

      if (rpcError) {
        console.error(`[Sync] Failed to process order ${orderId}:`, rpcError);
        throw new Error(`Atomic sync failed for order ${orderId}: ${rpcError.message}`);
      }

      existingLedgerIds.add(orderId);
      existingTxIds.add(orderId);
      newLastSyncedTs = Math.max(newLastSyncedTs, orderTs);
      added++;
    }

    // 9. Update sync state (only reached if all orders processed successfully)
    const safeNewMarker = Math.max(newLastSyncedTs, beginTime);
    const { error: stateError } = await supabase.from('sync_state').update({
      last_synced_order_ts: Math.max(safeNewMarker, lastSyncedOrderTs),
      last_sync_time: Date.now(),
      last_server_sync_status: `Success: Added ${added}, Skipped ${skipped} at ${new Date().toISOString()}`
    }).eq('id', 1);

    if (stateError) {
      console.error("[Sync] Failed to update sync state:", stateError);
      throw new Error(`Failed to update sync state: ${stateError.message}`);
    }

    return { added, skipped };

  } finally {
    // 11. Release lock
    await supabase.rpc('release_sync_lock', { p_owner_id: lockId });
  }
}
