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
    await requireFinanceRole(uid, supabase); // ADMIN/FINANCE only

    const { bankAccountId, amount, notes } = await req.json();

    const { data: bank, error: bankError } = await supabase
      .from("bank_accounts")
      .select("*")
      .eq("id", bankAccountId)
      .single();

    if (bankError || !bank) throw new Error("Bank account not found");

    const txId = crypto.randomUUID();

    // 1. Update bank balance
    const { error: updateError } = await supabase.from("bank_accounts")
      .update({ balance: Number(bank.balance) + amount, last_updated_at: new Date().toISOString() })
      .eq("id", bankAccountId);
    if (updateError) throw updateError;

    // 2. Insert FUND_BANK ledger entry
    const { error: ledgerError } = await supabase.from("financial_ledger").insert({
      id: txId,
      type: "FUND_BANK",
      amount,
      to_id: bankAccountId,
      to_label: bank.bank_name,
      created_by_uid: uid,
      notes,
      timestamp: Date.now()
    });
    if (ledgerError) throw ledgerError;

    return new Response(JSON.stringify({ txId }), {
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
