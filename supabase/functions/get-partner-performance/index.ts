import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, asNumber } from "../_shared/helpers.ts";
import { 
  _computeReconciledProfit,
  _buildDailyFlowMapV6,
  _buildLoanTimelineV6,
  _calculateInvestorDayV6,
  _normalizeDateValueHistory,
  formatDateKey
} from "../_shared/profitEngine.ts";


console.log("Get-Partner-Performance function started");

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });
  }

  try {
    const supabase = createServiceClient();
    
    // 1. Verify Auth
    await verifyAuth(req, supabase);

    // 2. Fetch all required data
    const { data: configData } = await supabase
      .from("system_config")
      .select("value")
      .eq("key", "openingCapital")
      .single();
    
    const openingCapital = asNumber(configData?.value || 300000);

    const { data: capitalHistoryRow } = await supabase
      .from("system_config")
      .select("value")
      .eq("key", "openingCapitalHistory")
      .maybeSingle();
    const openingCapitalHistory = _normalizeDateValueHistory(capitalHistoryRow?.value, openingCapital);

    const { data: investors } = await supabase.from("investors").select("*").eq("status", "active");
    const { data: partners } = await supabase.from("partners").select("*").eq("status", "active");

    const { data: ledgerRows, error: ledgerError } = await supabase
      .from("financial_ledger")
      .select("type,amount,timestamp")
      .in("type", ["DISTRIBUTE_VFCASH", "DISTRIBUTE_INSTAPAY"]);
    if (ledgerError) throw ledgerError;

    const { data: banks } = await supabase.from("bank_accounts").select("*");
    const { data: retailers } = await supabase.from("retailers").select("*");
    const { data: collectors } = await supabase.from("collectors").select("*");
    const { data: loans } = await supabase.from("loans").select("principal_amount,issued_at,repaid_at,amount_repaid,status");
    const { data: mobileNumbers } = await supabase.from("mobile_numbers").select("*");
    const { data: usdExchange } = await supabase.from("usd_exchange").select("*").eq("id", 1).single();

    const activeInvestors = (investors || []).sort((a, b) => 
      formatDateKey(a.investment_date).localeCompare(formatDateKey(b.investment_date))
    );

    const totalDistributionsSum = [...(investors || []), ...(partners || [])]
      .reduce((sum, p) => sum + asNumber(p.total_profit_paid || 0), 0);

    const dbData = {
      openingCapital,
      investors: activeInvestors,
      banks: banks || [],
      retailers: retailers || [],
      collectors: collectors || [],
      loans: loans || [],
      mobileNumbers: mobileNumbers || [],
      usdExchange: usdExchange || null
    };

    const health = _computeReconciledProfit(dbData, totalDistributionsSum);
    const totalBusinessNetProfit = health.netProfit;

    const dailyFlow = _buildDailyFlowMapV6(ledgerRows as any);
    const loanEvents = _buildLoanTimelineV6((loans || []) as any);

    let totalInvestorEarningsAll = 0;
    (activeInvestors as any[]).forEach((investor) => {
      const startDate = formatDateKey(investor.investment_date);
      Object.entries(dailyFlow)
        .filter(([dateKey]) => dateKey >= startDate)
        .forEach(([dateKey, flows]) => {
          const d = _calculateInvestorDayV6({
            investor,
            dateKey,
            vfFlow: asNumber((flows as any).vf),
            instaFlow: asNumber((flows as any).insta),
            activeInvestorsSorted: activeInvestors as any,
            openingCapitalHistory,
            loanEvents,
          });
          totalInvestorEarningsAll += d.profit;
        });
    });

    const partnerPool = Math.max(0, totalBusinessNetProfit - totalInvestorEarningsAll);

    const performance = (partners || []).map(partner => {
      const share = partnerPool * (asNumber(partner.share_percent) / 100);
      const totalPaid = asNumber(partner.total_profit_paid);
      return {
        partner_id: partner.id,
        name: partner.name,
        sharePercent: partner.share_percent,
        totalEarned: share,
        totalPaid,
        payableBalance: Math.max(0, share - totalPaid)
      };
    });

    return new Response(JSON.stringify({ 
      success: true,
      businessNetProfit: totalBusinessNetProfit,
      totalInvestorProfitDeducted: totalInvestorEarningsAll,
      partnerPool,
      partnerBreakdown: Object.fromEntries(performance.map((p) => [p.partner_id, p])),
      partners: performance,
      totalPayable: performance.reduce((s, p) => s + p.payableBalance, 0),
      assetsSummary: health
    }), { 
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } 
    });

  } catch (error: any) {
    console.error("[Get Partner Performance] Error:", error);
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 500, 
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } 
    });
  }
});
