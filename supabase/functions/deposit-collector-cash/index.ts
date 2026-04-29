import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, requireFinanceRole, resolveCollectorId } from "../_shared/helpers.ts";

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

    const body = await req.json();
    const { collectorId, bankAccountId, amount, notes } = body;

    if (!collectorId || !bankAccountId || amount <= 0) {
      return new Response(JSON.stringify({ error: "Invalid deposit request." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Resolve UUID → Firebase UID if the client sends a Supabase UUID
    const resolvedCollectorId = await resolveCollectorId(collectorId, supabase);
    const resolvedCallerUid  = await resolveCollectorId(uid, supabase);

    // COLLECTOR role: verify they are depositing their own cash
    if (role === "COLLECTOR") {
      const { data: collector } = await supabase
        .from("collectors")
        .select("id")
        .eq("id", resolvedCollectorId)
        .single();

      if (!collector || collector.id !== resolvedCallerUid) {
        return new Response(JSON.stringify({ error: "Forbidden: Unauthorized for this deposit" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // Bug 3 Fix: Single atomic RPC — deducts cash, credits bank, writes ledger
    // If any step fails the whole transaction rolls back automatically.
    const { data: txResult, error: txError } = await supabase.rpc("deposit_collector_cash_tx", {
      p_collector_id:   resolvedCollectorId,
      p_bank_account_id: bankAccountId,
      p_amount:         amount,
      p_notes:          notes || null,
      p_uid:            uid,
      p_timestamp:      Date.now(),
    });

    if (txError) throw txError;

    const result = Array.isArray(txResult) ? txResult[0] : txResult;

    if (!result.committed) {
      return new Response(
        JSON.stringify({ error: `Insufficient cash on hand. Available: ${result.new_cash_on_hand} EGP` }),
        { status: 412, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(JSON.stringify({ txId: result.tx_id }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: any) {
    console.error("[Deposit Collector Cash] Error:", err);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
