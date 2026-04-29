import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, getCallerRole, requireFinanceRole } from "../_shared/helpers.ts";

console.log("Correct-Ledger-Entry function started");

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
        JSON.stringify({ error: "Only admins can correct ledger entries" }),
        { status: 403, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    // 2. Parse Request
    const { ledgerId, newAmount, newNotes } = await req.json();

    if (!ledgerId || newAmount === undefined) {
      return new Response(
        JSON.stringify({ error: "ledgerId and newAmount are required" }),
        { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    // 3. Call RPC
    const { error } = await supabase.rpc('correct_financial_ledger_entry', {
      p_ledger_id: ledgerId,
      p_new_amount: newAmount,
      p_new_notes: newNotes || "System Correction",
      p_created_by_uid: uid
    });

    if (error) {
      console.error("[Correct Ledger Entry] RPC Error:", error);
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    return new Response(
      JSON.stringify({ success: true }),
      { 
        headers: { 
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        status: 200 
      }
    );
  } catch (error: any) {
    console.error("[Correct Ledger Entry] Error:", error);
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
