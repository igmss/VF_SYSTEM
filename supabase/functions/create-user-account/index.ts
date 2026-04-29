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
    await requireFinanceRole(uid, supabase);

    const { email, password, name, role, retailerId } = await req.json();

    // Validate
    const allowedRoles = ["ADMIN", "FINANCE", "COLLECTOR", "RETAILER"];
    if (!allowedRoles.includes(role)) {
      return new Response(JSON.stringify({ error: "Invalid role" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!password || password.length < 6) {
      return new Response(JSON.stringify({ error: "Password must be at least 6 characters" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (role === "RETAILER" && !retailerId) {
      return new Response(JSON.stringify({ error: "retailerId is required for RETAILER role" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (role === "RETAILER") {
      const { data: retailer, error: retailerError } = await supabase
        .from("retailers")
        .select("id")
        .eq("id", retailerId)
        .single();
      if (retailerError || !retailer) {
        return new Response(JSON.stringify({ error: "Retailer not found" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    // Create Auth User
    const { data: authUser, error: authError } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { name },
    });

    if (authError) {
      const msg = authError.message.toLowerCase();
      if (msg.includes("already") && (msg.includes("registered") || msg.includes("exists"))) {
        return new Response(JSON.stringify({ error: "already-exists" }), {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      throw authError;
    }

    const userRecord = authUser.user;

    // Insert into users table
    const nowIso = new Date().toISOString();
    const userPayload: any = {
      id: userRecord.id,
      email,
      name,
      role,
      is_active: true,
      created_at: nowIso,
    };
    if (role === "RETAILER") {
      userPayload.retailer_id = retailerId;
    }

    const { error: dbError } = await supabase.from("users").insert(userPayload);

    if (dbError) {
      // Rollback auth user
      await supabase.auth.admin.deleteUser(userRecord.id);
      throw dbError;
    }

    // If COLLECTOR, insert into collectors table
    if (role === "COLLECTOR") {
      const { error: collectorError } = await supabase.from("collectors").insert({
        id: userRecord.id,
        name,
        email,
        cash_on_hand: 0,
        cash_limit: 50000,
        total_collected: 0,
        total_deposited: 0,
        is_active: true,
      });

      if (collectorError) {
        // Rollback DB and Auth
        await supabase.from("users").delete().eq("id", userRecord.id);
        await supabase.auth.admin.deleteUser(userRecord.id);
        throw collectorError;
      }
    }

    return new Response(JSON.stringify({ uid: userRecord.id }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
