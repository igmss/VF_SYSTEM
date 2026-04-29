import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { processSync } from "../_shared/bybitHelpers.ts";
import { verifyAuth, requireFinanceRole } from "../_shared/helpers.ts";

console.log("Manual-Sync-Bybit function started");

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });
  }

  try {
    const supabase = createServiceClient();
    
    // 1. Verify Auth & Role (Allow service role to bypass)
    const authHeader = req.headers.get("Authorization");
    const isServiceRole = authHeader === `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
    
    if (!isServiceRole) {
      const { uid } = await verifyAuth(req, supabase);
      await requireFinanceRole(uid, supabase);
    }

    // 2. Parse Request
    let beginTimeOverride: number | null = null;
    let action: string | null = null;
    let apiKey: string | null = null;
    let apiSecret: string | null = null;

    try {
      const body = await req.json();
      action = body.action;
      apiKey = body.apiKey;
      apiSecret = body.apiSecret;
      if (body.beginTime) {
        beginTimeOverride = parseInt(body.beginTime);
      }
    } catch (e) {
      // Body might be empty or invalid, ignore
    }

    // 3. Handle Actions
    if (action === 'set_credentials') {
      if (!apiKey || !apiSecret) {
        throw new Error("Missing API Key or Secret");
      }

      const { error: upsertError } = await supabase.from('system_config').upsert({
        key: 'bybit_metadata',
        value: {
          apiKey,
          apiSecret,
          configured: true,
          updatedAt: new Date().toISOString()
        }
      });

      if (upsertError) throw upsertError;

      return new Response(
        JSON.stringify({ success: true, message: "Credentials saved successfully" }),
        { 
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
          status: 200 
        }
      );
    }

    // Default: Process Sync
    const result = await processSync(supabase, true, beginTimeOverride);

    return new Response(
      JSON.stringify(result),
      { 
        headers: { 
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        status: 200 
      }
    );
  } catch (error: any) {
    console.error("[Manual Sync] Error:", error);
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
