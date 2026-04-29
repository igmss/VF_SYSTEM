import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, requireFinanceRole } from "../_shared/helpers.ts";

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
    const role = await requireFinanceRole(uid, supabase, true);

    const { collectorId, vfNumberId, amount, notes } = await req.json();

    const { data: collector, error: collectorError } = await supabase
      .from("collectors")
      .select("*")
      .eq("id", collectorId)
      .single();

    if (collectorError || !collector) throw new Error("Collector not found");

    if (role === "COLLECTOR" && collector.id !== uid) {
      return new Response(JSON.stringify({ error: "Forbidden: Unauthorized for this collector" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Resolve VF number
    let vfNumber;
    if (vfNumberId) {
      const { data, error } = await supabase.from("mobile_numbers").select("*").eq("id", vfNumberId).single();
      if (error || !data) throw new Error("Mobile number not found");
      vfNumber = data;
    } else {
      const { data, error } = await supabase.from("mobile_numbers").select("*").eq("is_default", true).limit(1).single();
      if (error || !data) throw new Error("Default mobile number not found");
      vfNumber = data;
    }

    // Read system config
    const { data: configRes } = await supabase.from("system_config").select("value").eq("key", "collectorVfDepositFeePer1000").single();
    const feeRatePer1000 = configRes?.value || 7.0;

    // Compute
    const feeProfit = Math.round((amount / 1000) * Number(feeRatePer1000) * 100) / 100;
    const transferredAmount = Math.round((amount + feeProfit) * 100) / 100;

    // Atomic deduction
    const { data: deductResult, error: deductError } = await supabase.rpc("deduct_collector_cash", {
      p_collector_id: collectorId,
      p_amount: amount
    });

    if (deductError) throw deductError;
    const res = Array.isArray(deductResult) ? deductResult[0] : deductResult;
    if (!res.committed) {
      return new Response(JSON.stringify({ error: `Insufficient cash on hand. Available: ${res.cash_on_hand}` }), {
        status: 412,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const txId = crypto.randomUUID();
    const generatedTxId = crypto.randomUUID();
    const nowTs = Date.now();

    try {
      // 1. Insert DEPOSIT_TO_VFCASH ledger entry
      const { error: ledgerError } = await supabase.from("financial_ledger").insert({
        id: txId,
        type: "DEPOSIT_TO_VFCASH",
        amount,
        from_id: collectorId,
        to_id: vfNumber.id,
        to_label: vfNumber.phone_number,
        created_by_uid: uid,
        notes,
        timestamp: nowTs,
        transferred_amount: transferredAmount,
        fee_amount: feeProfit,
        fee_rate_per_1000: Number(feeRatePer1000),
        generated_transaction_id: generatedTxId
      });
      if (ledgerError) throw ledgerError;

      // 2. Update collector total_deposited
      await supabase.from("collectors")
        .update({ total_deposited: Number(collector.total_deposited) + amount })
        .eq("id", collectorId);

      // 3. Insert transactions row
      await supabase.from("transactions").insert({
        id: generatedTxId,
        phone_number: vfNumber.phone_number,
        amount: transferredAmount,
        bybit_order_id: "CLDV-" + txId.substring(0, 8),
        side: 1, // Incoming
        status: "COMPLETED",
        timestamp: new Date(nowTs).toISOString(),
        related_ledger_id: txId
      });

      // 4. Update mobile number usage
      await supabase.rpc("apply_mobile_number_usage_delta", {
        p_number_id: vfNumber.id,
        p_amount_delta: transferredAmount,
        p_direction: "incoming",
        p_timestamp_ms: nowTs
      });

      // 5. If profit > 0, insert profit ledger entry
      if (feeProfit > 0) {
        await supabase.from("financial_ledger").insert({
          type: "VFCASH_RETAIL_PROFIT",
          amount: feeProfit,
          created_by_uid: uid,
          related_ledger_id: txId,
          timestamp: nowTs,
          notes: `Profit from collector VF deposit (${collector.name})`
        });
      }

    } catch (err) {
      // Rollback deduction
      await supabase.from("collectors")
        .update({ cash_on_hand: Number(res.cash_on_hand) + amount })
        .eq("id", collectorId);
      throw err;
    }

    return new Response(JSON.stringify({
      txId,
      vfNumberId: vfNumber.id,
      vfPhone: vfNumber.phone_number,
      transferredAmount,
      feeAmount: feeProfit,
      feeRatePer1000: Number(feeRatePer1000)
    }), {
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
