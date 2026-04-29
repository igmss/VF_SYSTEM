import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, requireFinanceRole, computeDistributionAmounts } from "../_shared/helpers.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createServiceClient();
    const { uid } = await verifyAuth(req, supabase);
    await requireFinanceRole(uid, supabase);

    const { retailerId, fromVfNumberId, fromVfPhone, amount, fees, chargeFeesToRetailer, applyCredit, notes } = await req.json();

    // Phase 1: Compute amounts
    const { retailer, actualDebtIncrease, creditUsed } = await computeDistributionAmounts({
      supabase,
      retailerId,
      amount,
      fees,
      chargeFeesToRetailer,
      applyCredit
    });

    const totalDeduction = amount + fees;
    const nowTs = Date.now();
    const dateStr = new Date().toISOString().split("T")[0];

    // Phase 2: Atomic reservation on mobile number
    const { data: reserveResult, error: reserveError } = await supabase.rpc("increment_mobile_number_usage", {
      p_number_id: fromVfNumberId,
      p_amount_delta: totalDeduction,
      p_direction: "outgoing",
      p_timestamp_ms: nowTs,
      p_require_sufficient_balance: true
    });

    if (reserveError) throw reserveError;
    const res = Array.isArray(reserveResult) ? reserveResult[0] : reserveResult;
    if (!res.committed) {
      return new Response(JSON.stringify({ error: `Insufficient VF balance. Available: ${res.new_balance}` }), {
        status: 412,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const txId = crypto.randomUUID();
    const cashTxId = crypto.randomUUID();
    const feeTxId = crypto.randomUUID();

    try {
      // Phase 3: DB writes
      // 1. Insert DISTRIBUTE_VFCASH ledger entry
      await supabase.from("financial_ledger").insert({
        id: txId,
        type: "DISTRIBUTE_VFCASH",
        amount,
        from_id: fromVfNumberId,
        from_label: fromVfPhone,
        to_id: retailerId,
        to_label: retailer.name,
        created_by_uid: uid,
        notes: `${notes || ""} (Debt +${actualDebtIncrease} EGP${creditUsed > 0 ? `, -${creditUsed} Credit Used` : ""})`.trim(),
        timestamp: nowTs,
        generated_transaction_id: cashTxId
      });

      // 2. Insert transactions row
      await supabase.from("transactions").insert({
        id: cashTxId,
        phone_number: fromVfPhone,
        amount: totalDeduction,
        bybit_order_id: "DIST-" + txId.substring(0, 8),
        side: 0, // Outgoing
        status: "COMPLETED",
        timestamp: new Date(nowTs).toISOString(),
        related_ledger_id: txId
      });

      // 3. Update retailer
      await supabase.from("retailers").update({
        total_assigned: Number(retailer.total_assigned) + actualDebtIncrease,
        credit: Number(retailer.credit) - creditUsed,
        last_updated_at: new Date().toISOString()
      }).eq("id", retailerId);

      // 4. Handle fees
      if (fees > 0) {
        await supabase.from("financial_ledger").insert({
          id: feeTxId,
          type: "EXPENSE_VFCASH_FEE",
          amount: fees,
          from_id: fromVfNumberId,
          from_label: fromVfPhone,
          to_label: "System Fee",
          created_by_uid: uid,
          related_ledger_id: txId,
          timestamp: nowTs,
          notes: `Distribution fee for ${retailer.name}`
        });
      }

      // 5. Upsert flow summary
      await supabase.rpc("upsert_daily_flow_summary", {
        p_date_key: dateStr,
        p_vf_delta: amount,
        p_insta_delta: 0
      });

    } catch (err) {
      // Rollback VF reservation
      await supabase.rpc("increment_mobile_number_usage", {
        p_number_id: fromVfNumberId,
        p_amount_delta: -totalDeduction,
        p_direction: "outgoing",
        p_timestamp_ms: nowTs,
        p_clamp_at_zero: true
      });
      throw err;
    }

    return new Response(JSON.stringify({ txId, creditUsed, actualDebtIncrease }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
