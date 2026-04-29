import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, requireFinanceRole } from "../_shared/helpers.ts";

console.log("Record-Loan-Repayment function started");

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });
  }

  try {
    const supabase = createServiceClient();
    
    // 1. Verify Auth & Role
    const { uid } = await verifyAuth(req, supabase);
    await requireFinanceRole(uid, supabase);

    // 2. Parse Request
    const { loanId, amount } = await req.json();

    if (!loanId || !amount || amount <= 0) {
      return new Response(
        JSON.stringify({ error: "Missing loanId or invalid amount" }),
        { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    // 3. Call RPC
    const { data, error } = await supabase.rpc('record_loan_repayment', {
      p_loan_id: loanId,
      p_amount: amount,
      p_created_by_uid: uid
    });

    if (error) {
      console.error("[Record Loan Repayment] RPC Error:", error);
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
    console.error("[Record Loan Repayment] Error:", error);
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
