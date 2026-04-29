import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { processSync } from "../_shared/bybitHelpers.ts";

console.log("Sync-Bybit-Orders function started");

serve(async (req) => {
  try {
    const supabase = createServiceClient();
    const result = await processSync(supabase, false, null);

    return new Response(
      JSON.stringify(result),
      { 
        headers: { "Content-Type": "application/json" },
        status: 200 
      }
    );
  } catch (error: any) {
    console.error("[Sync] Unhandled error:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        headers: { "Content-Type": "application/json" },
        status: 500 
      }
    );
  }
});
