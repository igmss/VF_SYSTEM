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
    const { collectorId, retailerId, amount, notes } = body;
    let vfAmount = body.vfAmount || 0;
    let instaPayAmount = body.instaPayAmount || 0;

    // Backward compat
    if (vfAmount === 0 && instaPayAmount === 0) {
      vfAmount = amount;
    }

    // Validate
    if (amount <= 0) {
      return new Response(JSON.stringify({ error: "Amount must be greater than 0" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (Math.abs(vfAmount + instaPayAmount - amount) > 0.01) {
      return new Response(JSON.stringify({ error: "VF + InstaPay amounts must sum to total amount" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Resolve UUID collectorId to Firebase UID if necessary
    const resolvedCollectorId = await resolveCollectorId(collectorId, supabase);
    const resolvedCallerUid = await resolveCollectorId(uid, supabase);

    // Fetch in parallel
    const [collectorRes, retailerRes] = await Promise.all([
      supabase.from("collectors").select("*").eq("id", resolvedCollectorId).single(),
      supabase.from("retailers").select("*").eq("id", retailerId).single(),
    ]);

    if (collectorRes.error || !collectorRes.data) throw new Error("Collector not found");
    if (retailerRes.error || !retailerRes.data) throw new Error("Retailer not found");

    const collector = collectorRes.data;
    const retailer = retailerRes.data;

    // Authorization check for COLLECTOR
    if (role === "COLLECTOR") {
      if (collector.id !== resolvedCallerUid || retailer.assigned_collector_id !== resolvedCallerUid) {
        return new Response(JSON.stringify({ error: "Forbidden: Unauthorized for this collection" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // Compute VF split
    const pendingDebt = Math.max(0, retailer.total_assigned - retailer.total_collected);
    const vfAddedToCollected = pendingDebt > 0 ? Math.min(vfAmount, pendingDebt) : 0;
    const vfAddedToCredit = vfAmount - vfAddedToCollected;

    // Compute InstaPay split
    const instaPayPendingDebt = Math.max(0, retailer.insta_pay_total_assigned - retailer.insta_pay_total_collected);
    const ipAddedToCollected = instaPayPendingDebt > 0 ? Math.min(instaPayAmount, instaPayPendingDebt) : 0;
    const ipAddedToCredit = instaPayAmount - ipAddedToCollected;

    const addedToCollected = vfAddedToCollected + ipAddedToCollected;
    const addedToCredit = vfAddedToCredit + ipAddedToCredit;

    // Prepare notes
    let finalNotes = notes || "";
    if (addedToCredit > 0) {
      finalNotes = `(+${addedToCredit.toFixed(0)} EGP added to Credit)\n${finalNotes}`.trim();
    }

    const instaTxId = crypto.randomUUID();
    const timestamp = Date.now();

    // Atomic transaction via RPC
    const { data: txResult, error: txError } = await supabase.rpc("collect_retailer_cash_tx", {
      p_collector_id: resolvedCollectorId,
      p_retailer_id: retailerId,
      p_amount: amount,
      p_vf_amount: vfAmount,
      p_insta_pay_amount: instaPayAmount,
      p_notes: finalNotes,
      p_vf_collected: vfAddedToCollected,
      p_ip_collected: ipAddedToCollected,
      p_added_to_credit: addedToCredit,
      p_uid: uid,
      p_timestamp: timestamp,
      p_insta_tx_id: instaTxId
    });

    if (txError) throw txError;

    const result = Array.isArray(txResult) ? txResult[0] : txResult;
    const { tx_id: txId, insta_tx_id: resultInstaTxId } = result;

    return new Response(JSON.stringify({ 
      txId, 
      instaTxId: instaPayAmount > 0 ? resultInstaTxId : null, 
      addedToCollected, 
      addedToCredit 
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
