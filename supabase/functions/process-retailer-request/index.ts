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
    await requireFinanceRole(uid, supabase);

    const body = await req.json();
    const { 
      requestId, 
      status, 
      proofImageUrl, 
      adminNotes,
      retailerId,
      fromVfNumberId,
      amount,
      fees,
      chargeFeesToRetailer,
      applyCredit
    } = body;

    if (status === 'COMPLETED') {
      if (!fromVfNumberId || !amount) {
        throw new Error("Missing required fields for approval");
      }

      const { error: rpcError } = await supabase.rpc('approve_retailer_request', {
        p_request_id: requestId,
        p_admin_uid: uid,
        p_from_vf_number_id: fromVfNumberId,
        p_amount: amount,
        p_fees: fees || 0,
        p_charge_fees_to_retailer: chargeFeesToRetailer || false,
        p_apply_credit: applyCredit || false,
        p_admin_notes: adminNotes || '',
        p_proof_image_url: proofImageUrl || ''
      });

      if (rpcError) throw rpcError;
    } else if (status === 'REJECTED') {
      const { error: rpcError } = await supabase.rpc('reject_retailer_request', {
        p_request_id: requestId,
        p_admin_uid: uid,
        p_reason: adminNotes || 'Rejected by admin'
      });

      if (rpcError) throw rpcError;
    } else {
      throw new Error(`Invalid status: ${status}`);
    }

    return new Response(JSON.stringify({ success: true }), {
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
