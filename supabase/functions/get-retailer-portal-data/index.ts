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
    
    // 1. Get user role and retailer info
    const { data: user, error: userError } = await supabase
      .from('users')
      .select('role, retailer_id')
      .eq('id', uid)
      .single();
    
    if (userError || !user) throw new Error("User not found");

    if (!['RETAILER', 'ADMIN', 'FINANCE'].includes(user.role)) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 403, headers: corsHeaders });
    }

    const body = await req.json();
    let retailerId = body.retailerId?.toString().trim() || '';
    
    if (user.role === 'RETAILER') {
      retailerId = user.retailer_id?.toString() || '';
      if (!retailerId) {
        return new Response(JSON.stringify({ error: "Your account is not linked to a retailer profile." }), { status: 400, headers: corsHeaders });
      }
    } else if (!retailerId) {
      return new Response(JSON.stringify({ error: "retailerId is required." }), { status: 400, headers: corsHeaders });
    }

    // Auth check for Retailer
    if (user.role === 'RETAILER' && user.retailer_id?.toString() !== retailerId) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 403, headers: corsHeaders });
    }

    // 2. Setup Time Range
    const now = Date.now();
    const startMs = body.startMs != null ? parseInt(body.startMs) : now - 24 * 60 * 60 * 1000;
    const endMs = body.endMs != null ? parseInt(body.endMs) : now;

    // 3. Fetch Data in Parallel
    const [retailerRes, ledgerRes] = await Promise.all([
      supabase.from('retailers').select('*').eq('id', retailerId).single(),
      supabase.from('financial_ledger')
        .select('*')
        .or(`from_id.eq.${retailerId},to_id.eq.${retailerId}`)
        .gte('timestamp', startMs)
        .lte('timestamp', endMs)
        .order('timestamp', { ascending: false })
    ]);

    if (retailerRes.error) throw retailerRes.error;
    if (ledgerRes.error) throw ledgerRes.error;

    return new Response(
      JSON.stringify({
        retailer: retailerRes.data,
        retailerId,
        activity: ledgerRes.data,
        range: { startMs, endMs },
      }),
      { 
        status: 200, 
        headers: { ...corsHeaders, "Content-Type": "application/json" } 
      }
    );

  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
