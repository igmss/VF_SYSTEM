import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, getCallerRole } from "../_shared/helpers.ts";

console.log("Pay-Partner-Profit function started");

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });
  }

  try {
    const supabase = createServiceClient();
    
    // 1. Verify Auth & Admin Role
    const { uid } = await verifyAuth(req, supabase);
    const role = await getCallerRole(uid, supabase);
    if (role !== 'ADMIN') {
      return new Response(
        JSON.stringify({ error: "Only admins can pay partner profit" }),
        { status: 403, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    // 2. Parse Request
    const { partnerId, amount, paymentSourceType, paymentSourceId, notes } = await req.json();

    if (!partnerId || !amount || amount <= 0 || !paymentSourceType || !paymentSourceId) {
      return new Response(
        JSON.stringify({ error: "partnerId, amount, paymentSourceType, and paymentSourceId are required" }),
        { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    // 3. Call RPC
    const { data, error } = await supabase.rpc('record_partner_payout', {
      p_partner_id: partnerId,
      p_amount: amount,
      p_payment_source_type: paymentSourceType,
      p_payment_source_id: paymentSourceId,
      p_notes: notes || "Partner Profit Payout",
      p_created_by_uid: uid
    });

    if (error) {
      console.error("[Pay Partner Profit] RPC Error:", error);
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    return new Response(
      JSON.stringify(data[0]),
      { 
        headers: { 
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        status: 200 
      }
    );
  } catch (error: any) {
    console.error("[Pay Partner Profit] Error:", error);
    const status = error instanceof Response ? (error as any).status : 500;
    const message = error instanceof Response ? await error.text() : error.message;

    return new Response(
      JSON.stringify({ error: message }),
      { 
        headers: { 
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        status: status || 500
      }
    );
  }
});
