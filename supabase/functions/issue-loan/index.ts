import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, requireFinanceRole } from "../_shared/helpers.ts";

console.log("Issue-Loan function started");

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
    const { sourceType, sourceId, borrowerName, borrowerPhone, amount, notes } = await req.json();

    if (!sourceType || !sourceId || !borrowerName || !amount || amount <= 0) {
      return new Response(
        JSON.stringify({ error: "Missing required fields or invalid amount" }),
        { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    // 3. Call RPC
    const { data, error } = await supabase.rpc('issue_loan', {
      p_source_type: sourceType,
      p_source_id: sourceId,
      p_borrower_name: borrowerName,
      p_borrower_phone: borrowerPhone || "",
      p_amount: amount,
      p_notes: notes || "",
      p_created_by_uid: uid
    });

    if (error) {
      console.error("[Issue Loan] RPC Error:", error);
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
    console.error("[Issue Loan] Error:", error);
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
