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

    const { retailerId, bankAccountId, amount, fees, applyCredit, notes } = await req.json();

    // Phase 1: Fetch and Compute
    const [retailerRes, bankRes] = await Promise.all([
      supabase.from("retailers").select("*").eq("id", retailerId).single(),
      supabase.from("bank_accounts").select("*").eq("id", bankAccountId).single(),
    ]);

    if (retailerRes.error || !retailerRes.data) throw new Error("Retailer not found");
    if (bankRes.error || !bankRes.data) throw new Error("Bank account not found");

    const retailer = retailerRes.data;
    const bank = bankRes.data;

    const profitPer1000 = retailer.insta_pay_profit_per_1000 || 0;
    const profitAmount = (amount / 1000) * Number(profitPer1000);
    let actualDebtIncrease = Math.ceil(amount + profitAmount);
    let creditUsed = 0;

    if (applyCredit && Number(retailer.credit) > 0) {
      creditUsed = Math.min(Number(retailer.credit), actualDebtIncrease);
      actualDebtIncrease -= creditUsed;
    }

    const totalDeduction = amount + fees;
    const nowTs = Date.now();
    const dateStr = new Date().toISOString().split("T")[0];

    // Phase 2: Atomic bank deduction
    const { data: deductResult, error: deductError } = await supabase.rpc("deduct_bank_balance", {
      p_bank_id: bankAccountId,
      p_amount: totalDeduction
    });

    if (deductError) throw deductError;
    const res = Array.isArray(deductResult) ? deductResult[0] : deductResult;
    if (!res.committed) {
      return new Response(JSON.stringify({ error: `Insufficient bank balance. Available: ${res.new_balance}` }), {
        status: 412,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const txId = crypto.randomUUID();
    const profitTxId = crypto.randomUUID();
    const feeTxId = crypto.randomUUID();

    try {
      // Phase 3: DB writes
      // 1. Insert DISTRIBUTE_INSTAPAY ledger entry
      await supabase.from("financial_ledger").insert({
        id: txId,
        type: "DISTRIBUTE_INSTAPAY",
        amount,
        from_id: bankAccountId,
        from_label: bank.bank_name,
        to_id: retailerId,
        to_label: retailer.name,
        created_by_uid: uid,
        notes: `${notes || ""} (Debt +${actualDebtIncrease} EGP${creditUsed > 0 ? `, -${creditUsed} Credit Used` : ""})`.trim(),
        timestamp: nowTs
      });

      // 2. Update retailer
      await supabase.from("retailers").update({
        insta_pay_total_assigned: Number(retailer.insta_pay_total_assigned) + actualDebtIncrease,
        credit: Number(retailer.credit) - creditUsed,
        last_updated_at: new Date().toISOString()
      }).eq("id", retailerId);

      // 3. Handle profit
      if (profitAmount > 0) {
        await supabase.from("financial_ledger").insert({
          id: profitTxId,
          type: "INSTAPAY_DIST_PROFIT",
          amount: profitAmount,
          from_id: retailerId,
          from_label: retailer.name,
          to_label: "System Profit",
          created_by_uid: uid,
          related_ledger_id: txId,
          timestamp: nowTs,
          notes: `Profit from InstaPay distribution to ${retailer.name}`
        });
      }

      // 4. Handle fees
      if (fees > 0) {
        await supabase.from("financial_ledger").insert({
          id: feeTxId,
          type: "EXPENSE_INSTAPAY_FEE",
          amount: fees,
          from_id: bankAccountId,
          from_label: bank.bank_name,
          created_by_uid: uid,
          related_ledger_id: txId,
          timestamp: nowTs,
          notes: `InstaPay distribution fee for ${retailer.name}`
        });
      }

      // 5. Upsert flow summary
      await supabase.rpc("upsert_daily_flow_summary", {
        p_date_key: dateStr,
        p_vf_delta: 0,
        p_insta_delta: amount
      });

    } catch (err) {
      // Rollback bank deduction
      await supabase.from("bank_accounts")
        .update({ balance: Number(res.balance) + totalDeduction })
        .eq("id", bankAccountId);
      throw err;
    }

    return new Response(JSON.stringify({ txId, actualDebtIncrease, profitAmount, fees }), {
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
