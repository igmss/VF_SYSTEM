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

    const { bankAccountId, newBalance, notes } = await req.json();

    const { data: bank, error: bankError } = await supabase
      .from("bank_accounts")
      .select("*")
      .eq("id", bankAccountId)
      .single();

    if (bankError || !bank) throw new Error("Bank account not found");

    const diff = newBalance - Number(bank.balance);
    if (Math.abs(diff) < 0.0001) {
      return new Response(JSON.stringify({ txId: null, unchanged: true }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const txId = crypto.randomUUID();

    // 1. Update bank balance
    const { error: updateError } = await supabase.from("bank_accounts")
      .update({ balance: newBalance, last_updated_at: new Date().toISOString() })
      .eq("id", bankAccountId);
    if (updateError) throw updateError;

    // 2. Insert ledger entry
    const type = diff >= 0 ? "FUND_BANK" : "BANK_DEDUCTION";
    const amount = Math.abs(diff);
    const finalNotes = `BALANCE_CORRECTION: ${notes || ""}`.trim();

    const ledgerPayload: any = {
      id: txId,
      type,
      amount,
      created_by_uid: uid,
      notes: finalNotes,
      timestamp: Date.now()
    };

    if (diff >= 0) {
      ledgerPayload.to_id = bankAccountId;
      ledgerPayload.to_label = bank.bank_name;
    } else {
      ledgerPayload.from_id = bankAccountId;
      ledgerPayload.from_label = bank.bank_name;
    }

    const { error: ledgerError } = await supabase.from("financial_ledger").insert(ledgerPayload);
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
