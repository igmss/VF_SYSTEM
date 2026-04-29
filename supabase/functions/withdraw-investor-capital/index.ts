import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, getCallerRole, requireFinanceRole } from "../_shared/helpers.ts";

console.log("Withdraw-Investor-Capital function started");

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
        JSON.stringify({ error: "Only admins can withdraw investor capital" }),
        { status: 403, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    // 2. Parse Request
    const { investorId, amount, bankAccountId, notes } = await req.json();

    if (!investorId || !amount || amount <= 0 || !bankAccountId) {
      return new Response(
        JSON.stringify({ error: "investorId, amount, and bankAccountId are required" }),
        { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    // 3. Call RPC
    const { data, error } = await supabase.rpc('withdraw_investor_capital', {
      p_investor_id: investorId,
      p_amount: amount,
      p_bank_account_id: bankAccountId,
      p_notes: notes || "Capital Withdrawal",
      p_created_by_uid: uid
    });

    if (error) {
      console.error("[Withdraw Investor Capital] RPC Error:", error);
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
    console.error("[Withdraw Investor Capital] Error:", error);
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
