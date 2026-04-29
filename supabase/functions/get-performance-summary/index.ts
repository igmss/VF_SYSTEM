import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, requireFinanceRole, parseBody } from "../_shared/helpers.ts";

console.log("Get-Performance-Summary function started");

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
    const { startDateTs, endDateTs } = await parseBody(req);


    if (!startDateTs || !endDateTs) {
      return new Response(
        JSON.stringify({ error: "startDateTs and endDateTs are required" }),
        { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    // 3. Call RPC
    const { data, error } = await supabase.rpc('get_daily_performance', {
      p_start_date_ts: startDateTs,
      p_end_date_ts: endDateTs
    });

    if (error) {
      console.error("[Get Performance Summary] RPC Error:", error);
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
    console.error("[Get Performance Summary] Error:", error);
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
