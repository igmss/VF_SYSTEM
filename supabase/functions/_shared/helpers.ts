import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// ─── Interfaces ───────────────────────────────────────────────────────────────

export interface MobileNumber {
  id: string;
  phone_number: string;
  initial_balance: number;
  in_total_used: number;
  out_total_used: number;
  in_daily_used: number;
  in_daily_limit: number;
  out_daily_used: number;
  out_daily_limit: number;
  in_monthly_used: number;
  in_monthly_limit: number;
  out_monthly_used: number;
  out_monthly_limit: number;
  is_default: boolean;
  created_at: string;
  last_updated_at: string;
}

export interface Retailer {
  id: string;
  name: string;
  phone: string;
  assigned_collector_id: string;
  discount_per_1000: number;
  insta_pay_profit_per_1000: number;
  total_assigned: number;
  total_collected: number;
  insta_pay_total_assigned: number;
  insta_pay_total_collected: number;
  insta_pay_pending_debt: number;
  pending_debt: number;
  credit: number;
  area: string;
  is_active: boolean;
}

export interface LedgerEntry {
  id: string;
  type: string;
  amount: number;
  from_id?: string;
  from_label?: string;
  to_id?: string;
  to_label?: string;
  created_by_uid?: string;
  notes?: string;
  timestamp: number;
  bybit_order_id?: string;
  related_ledger_id?: string;
  generated_transaction_id?: string;
  transferred_amount?: number;
  fee_amount?: number;
  fee_rate_per_1000?: number;
  collected_portion?: number;
  credit_portion?: number;
  usdt_price?: number;
  usdt_quantity?: number;
  profit_per_1000?: number;
  category?: string;
  payment_method?: string;
}

export interface Transaction {
  id: string;
  phone_number: string;
  amount: number;
  currency: string;
  timestamp: string | number;
  bybit_order_id: string;
  status: string;
  payment_method: string;
  side: number;
  chat_history?: string;
  price?: number;
  quantity?: number;
  token?: string;
  related_ledger_id?: string;
}

// ─── Pure Functions ───────────────────────────────────────────────────────────

export function asNumber(value: unknown): number {
  if (value == null) return 0;
  if (typeof value === "number") return value;
  const parsed = parseFloat(value as string);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function getMobileNumberBalance(number: MobileNumber): number {
  return asNumber(number.initial_balance) + asNumber(number.in_total_used) - asNumber(number.out_total_used);
}

export function getRetailerOutstandingDebt(retailer: Retailer): number {
  const outstanding = asNumber(retailer.total_assigned) - asNumber(retailer.total_collected);
  return outstanding > 0 ? outstanding : 0;
}

export function getRetailerInstaPayOutstandingDebt(retailer: Retailer): number {
  const outstanding = asNumber(retailer.insta_pay_total_assigned) - asNumber(retailer.insta_pay_total_collected);
  return outstanding > 0 ? outstanding : 0;
}

export function getTransactionTimestampMs(tx: Partial<Transaction> | null): number {
  if (!tx) return Date.now();
  if (typeof tx.timestamp === "number") return tx.timestamp;
  const parsed = Date.parse((tx.timestamp as string) || "");
  return Number.isFinite(parsed) ? parsed : Date.now();
}

export function safeDate(val: unknown, fallback: string): Date {
  const d = new Date(val as string);
  return isNaN(d.getTime()) ? new Date(fallback) : d;
}

export function sumEntryAmounts(entries: LedgerEntry[]): number {
  return entries.reduce((sum, entry) => sum + asNumber(entry.amount), 0);
}

export function buildCorrectionNote(existingNotes: string, originalAmount: number, correctAmount: number, reason: string): string {
  return `[Corrected] ${reason} | Original: ${originalAmount} → ${correctAmount}\n${existingNotes || ""}`.trim();
}

export function parseCollectCreditPortion(tx: LedgerEntry): number {
  const explicit = asNumber(tx.credit_portion);
  if (explicit > 0) return explicit;
  const notes = tx.notes ? tx.notes.toString() : "";
  const match = notes.match(/\(\+([0-9]+(?:\.[0-9]+)?) EGP added to Credit\)/i);
  return match ? asNumber(match[1]) : 0;
}

export function stripCollectCreditNote(notes: string): string {
  return (notes || "")
    .replace(/\s*\(\+[0-9]+(?:\.[0-9]+)? EGP added to Credit\)/ig, "")
    .trim();
}

export function parseDistributionDebtIncrease(notes: string, fallback: number): number {
  const noteText = notes ? notes.toString() : "";
  const match = noteText.match(/Debt \+([0-9]+(?:\.[0-9]+)?) EGP/i);
  return match ? asNumber(match[1]) : fallback;
}

export function parseDistributionCreditUsed(notes: string): number {
  const noteText = notes ? notes.toString() : "";
  const match = noteText.match(/-([0-9]+(?:\.[0-9]+)?) Credit Used/i);
  return match ? asNumber(match[1]) : 0;
}

// ─── Database-backed Functions ────────────────────────────────────────────────

export async function getCallerRole(uid: string, supabase: SupabaseClient): Promise<string | null> {
  if (uid === "SERVICE_ROLE") return "ADMIN";
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(uid);
  
  let query = supabase.from("users").select("role");
  
  if (isUuid) {
    // Safe to check both
    query = query.or(`firebase_uid.eq.${uid},id.eq.${uid}`);
  } else {
    // Only check firebase_uid to avoid UUID cast error on 'id'
    query = query.eq("firebase_uid", uid);
  }

  const { data, error } = await query.single();
  if (error || !data) return null;
  return data.role;
}

export async function requireFinanceRole(uid: string, supabase: SupabaseClient, allowCollector = false): Promise<string> {
  if (uid === "SERVICE_ROLE") return "ADMIN";

  const role = await getCallerRole(uid, supabase);
  const allowed = allowCollector
    ? ["ADMIN", "FINANCE", "COLLECTOR"]
    : ["ADMIN", "FINANCE"];
    
  if (!role || !allowed.includes(role)) {
    throw new Error("Unauthorized");
  }
  return role;
}


export async function getGeneratedTransactions(prefix: string, supabase: SupabaseClient): Promise<Transaction[]> {
  const { data, error } = await supabase
    .from("transactions")
    .select("id, amount, bybit_order_id, phone_number, timestamp, status, payment_method, currency, side")
    .eq("bybit_order_id", prefix);

  if (error) return [];
  return data || [];
}

export async function getRelatedLedgerEntries(relatedLedgerId: string, types: string[] | null, supabase: SupabaseClient): Promise<LedgerEntry[]> {
  let query = supabase
    .from("financial_ledger")
    .select("*")
    .eq("related_ledger_id", relatedLedgerId);

  if (types && types.length > 0) {
    query = query.in("type", types);
  }

  const { data, error } = await query;
  if (error) return [];
  return data || [];
}

export interface DistributionParams {
  supabase: SupabaseClient;
  retailerId: string;
  amount: number;
  fees: number;
  chargeFeesToRetailer: boolean;
  applyCredit: boolean;
}

export async function computeDistributionAmounts({
  supabase,
  retailerId,
  amount,
  fees,
  chargeFeesToRetailer,
  applyCredit
}: DistributionParams) {
  const { data: retailer, error } = await supabase
    .from("retailers")
    .select("*")
    .eq("id", retailerId)
    .single();

  if (error || !retailer) throw new Error("Retailer not found.");

  const discountPer1000 = asNumber(retailer.discount_per_1000);
  const discountAmount = (amount / 1000.0) * discountPer1000;
  const feeToCharge = chargeFeesToRetailer ? fees : 0.0;
  let actualDebtIncrease = Math.ceil(amount + discountAmount + feeToCharge);
  let creditUsed = 0.0;

  const currentCredit = asNumber(retailer.credit);
  if (applyCredit && currentCredit > 0) {
    creditUsed = Math.min(currentCredit, actualDebtIncrease);
    actualDebtIncrease -= creditUsed;
  }

  return { retailer, actualDebtIncrease, creditUsed };
}

export async function verifyAuth(req: Request, supabase: SupabaseClient): Promise<{ uid: string; user: any; isServiceRole?: boolean }> {
  const authHeader = req.headers.get("Authorization");
  
  // Check for Service Role Token by decoding the JWT
  if (authHeader && authHeader.startsWith("Bearer ")) {
    const token = authHeader.split("Bearer ")[1];
    try {
      const payload = JSON.parse(atob(token.split('.')[1]));
      if (payload.role === 'service_role') {
        return { uid: "SERVICE_ROLE", user: { id: "SERVICE_ROLE", aud: "authenticated", role: "service_role" }, isServiceRole: true };
      }
    } catch (e) {
      // Ignore parse errors and fall through
    }
  }

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    throw new Response(
      JSON.stringify({ error: "Missing or invalid Authorization header" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const token = authHeader.split("Bearer ")[1];
  const { data: { user }, error } = await supabase.auth.getUser(token);

  if (error || !user) {
    throw new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  return { uid: user.id, user };
}

export async function parseBody(req: Request): Promise<any> {
  try {
    return await req.json();
  } catch (e) {
    return {};
  }
}

export async function resolveCollectorId(collectorId: string, supabase: SupabaseClient): Promise<string> {
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(collectorId);
  if (!isUuid) return collectorId;

  const { data } = await supabase.from("users").select("firebase_uid").eq("id", collectorId).single();
  if (data && data.firebase_uid) {
    return data.firebase_uid;
  }
  return collectorId;
}
