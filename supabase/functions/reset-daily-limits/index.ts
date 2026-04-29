import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";

console.log("Reset-Daily-Limits function started");

serve(async (req) => {
  try {
    const supabase = createServiceClient();

    // Call the dedicated RPC for atomic reset
    const { error: rpcError } = await supabase.rpc('reset_daily_limits');
    
    if (rpcError) throw rpcError;

    // Update system config marker
    const resetTime = Date.now();
    await supabase.from('system_config').upsert({ 
      key: 'lastDailyReset', 
      value: { timestamp: resetTime } 
    });

    return new Response(
      JSON.stringify({ success: true, resetAt: resetTime }),
      { 
        headers: { "Content-Type": "application/json" },
        status: 200 
      }
    );
  } catch (error: any) {
    console.error("[Reset] Error:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        headers: { "Content-Type": "application/json" },
        status: 500 
      }
    );
  }
});
