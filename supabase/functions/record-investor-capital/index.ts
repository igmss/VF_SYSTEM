import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, requireFinanceRole, resolveCollectorId } from "../_shared/helpers.ts";

console.log("Record-Investor-Capital function started");

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });
  }

  try {
    const supabase = createServiceClient();
    
    // 1. Verify Auth & Admin Role
    const { uid } = await verifyAuth(req, supabase);
    const role = await requireFinanceRole(uid, supabase);
    if (role !== 'ADMIN') {
      return new Response(
        JSON.stringify({ error: "Only admins can record investor capital" }),
        { status: 403, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    // 2. Parse Request
    const { name, phone, investedAmount, initialBusinessCapital, profitSharePercent, investmentDate, periodDays, bankAccountId, notes } = await req.json();

    if (!investedAmount || investedAmount <= 0 || !bankAccountId) {
      return new Response(
        JSON.stringify({ error: "Invested amount and bankAccountId are required" }),
        { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    // 3. Call RPC
    const { data, error } = await supabase.rpc('record_investor_capital', {
      p_name: name || "Investor",
      p_phone: phone || "",
      p_invested_amount: investedAmount,
      p_initial_business_capital: initialBusinessCapital || 0,
      p_profit_share_percent: profitSharePercent || 0,
      p_investment_date: investmentDate || Date.now(),
      p_period_days: periodDays || 30,
      p_bank_account_id: bankAccountId,
      p_notes: notes || "",
      p_created_by_uid: uid
    });

    if (error) {
      console.error("[Record Investor Capital] RPC Error:", error);
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
    console.error("[Record Investor Capital] Error:", error);
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
