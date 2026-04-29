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

    const { bankAccountId, amount, notes } = await req.json();

    const { data: bank, error: bankError } = await supabase
      .from("bank_accounts")
      .select("*")
      .eq("id", bankAccountId)
      .single();

    if (bankError || !bank) throw new Error("Bank account not found");

    // Atomic deduction
    const { data: deductResult, error: deductError } = await supabase.rpc("deduct_bank_balance", {
      p_bank_id: bankAccountId,
      p_amount: amount
    });

    if (deductError) throw deductError;
    const res = Array.isArray(deductResult) ? deductResult[0] : deductResult;

    if (!res.committed) {
      return new Response(JSON.stringify({ error: "Bank balance cannot go negative." }), {
        status: 412,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const txId = crypto.randomUUID();

    try {
      // Insert BANK_DEDUCTION ledger entry
      const { error: ledgerError } = await supabase.from("financial_ledger").insert({
        id: txId,
        type: "BANK_DEDUCTION",
        amount,
        from_id: bankAccountId,
        from_label: bank.bank_name,
        created_by_uid: uid,
        notes,
        timestamp: Date.now()
      });
      if (ledgerError) throw ledgerError;

    } catch (err) {
      // Rollback deduction
      await supabase.from("bank_accounts")
        .update({ balance: Number(res.new_balance) + amount })
        .eq("id", bankAccountId);
      throw err;
    }

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
