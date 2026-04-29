import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, parseBody, asNumber } from "../_shared/helpers.ts";
import { 
  _buildDailyFlowMapV6,
  _buildLoanTimelineV6,
  _calculateInvestorDayV6,
  _normalizeDateValueHistory,
  formatDateKey
} from "../_shared/profitEngine.ts";


console.log("Get-Investor-Performance function started");

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });
  }

  try {
    const supabase = createServiceClient();
    
    // 1. Verify Auth
    await verifyAuth(req, supabase);

    // 2. Parse Request
    const body = await parseBody(req);
    const investor_id = body?.investor_id ?? body?.investorId ?? body?.investor_id;


    // 3. Fetch Data
    // We need openingCapital from system_config
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

    const { data: ledgerRows, error: ledgerError } = await supabase
      .from("financial_ledger")
      .select("type,amount,timestamp")
      .in("type", ["DISTRIBUTE_VFCASH", "DISTRIBUTE_INSTAPAY"]);
    if (ledgerError) throw ledgerError;

    const { data: investors, error: invError } = await supabase
      .from("investors")
      .select("*")
      .eq("status", "active");
    if (invError) throw invError;

    const { data: loans, error: loanError } = await supabase
      .from("loans")
      .select("principal_amount,issued_at,repaid_at");
    if (loanError) throw loanError;

    // 4. Calculate Performance
    const activeInvestors = (investors || []).sort((a, b) => 
      formatDateKey(a.investment_date).localeCompare(formatDateKey(b.investment_date))
    );

    if (investor_id) {
      const investor = activeInvestors.find((i) => i.id === investor_id);
      if (!investor) {
        return new Response(JSON.stringify({ success: false, error: "Investor not found or inactive." }), {
          status: 404,
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
        });
      }

      const dailyFlow = _buildDailyFlowMapV6(ledgerRows as any);
      const loanEvents = _buildLoanTimelineV6((loans || []) as any);
      const startDate = formatDateKey(investor.investment_date);

      let totalEarned = 0;
      const dailyBreakdown: any[] = [];

      Object.keys(dailyFlow)
        .filter((d) => d >= startDate)
        .sort((a, b) => b.localeCompare(a))
        .forEach((dateKey) => {
          const { vf, insta } = dailyFlow[dateKey];
          const d = _calculateInvestorDayV6({
            investor: investor as any,
            dateKey,
            vfFlow: vf,
            instaFlow: insta,
            activeInvestorsSorted: activeInvestors as any,
            openingCapitalHistory,
            loanEvents,
          });
          totalEarned += d.profit;
          dailyBreakdown.push({
            date: dateKey,
            vfFlow: vf,
            instaFlow: insta,
            effectiveCap: d.effectiveCap,
            hurdle: d.hurdle,
            excessFlow: d.excessFlow,
            vfExcess: d.vfExcess,
            instaExcess: d.instaExcess,
            vfProfit: d.vfProfit,
            instaProfit: d.instaProfit,
            profit: d.profit,
          });
        });

      const totalPaid = asNumber((investor as any).total_profit_paid);
      const totalVfFlow = dailyBreakdown.reduce((s, d) => s + asNumber(d.vfExcess), 0);
      const totalInstaFlow = dailyBreakdown.reduce((s, d) => s + asNumber(d.instaExcess), 0);
      const payableBalance = Math.max(0, totalEarned - totalPaid);

      const perf = [{
        investor_id: investor.id,
        name: investor.name,
        totalEarned,
        totalPaid,
        totalVfFlow,
        totalInstaFlow,
        payableBalance,
        dailyBreakdown,
      }];

      return new Response(JSON.stringify({
        success: true,
        performance: perf,
        totalEarned,
        totalPaid,
        totalPayable: payableBalance,
        totalVfFlow,
        totalInstaFlow,
      }), {
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }

    const dailyFlow = _buildDailyFlowMapV6(ledgerRows as any);
    const loanEvents = _buildLoanTimelineV6((loans || []) as any);

    let globalTotalEarned = 0;
    let globalTotalPaid = 0;
    let globalTotalPayable = 0;
    let globalTotalVfFlow = 0;
    let globalTotalInstaFlow = 0;

    const performance = (activeInvestors as any[]).map((investor) => {
      const startDate = formatDateKey(investor.investment_date);
      let totalEarned = 0;
      let totalVfFlow = 0;
      let totalInstaFlow = 0;

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
          totalEarned += d.profit;
          totalVfFlow += d.vfExcess;
          totalInstaFlow += d.instaExcess;
        });

      const totalPaid = asNumber(investor.total_profit_paid);
      const payableBalance = Math.max(0, totalEarned - totalPaid);

      globalTotalEarned += totalEarned;
      globalTotalPaid += totalPaid;
      globalTotalPayable += payableBalance;
      globalTotalVfFlow += totalVfFlow;
      globalTotalInstaFlow += totalInstaFlow;

      return {
        investor_id: investor.id,
        name: investor.name,
        totalEarned,
        totalPaid,
        totalVfFlow,
        totalInstaFlow,
        payableBalance,
      };
    });

    return new Response(JSON.stringify({
      success: true,
      performance,
      totalEarned: globalTotalEarned,
      totalPaid: globalTotalPaid,
      totalPayable: globalTotalPayable,
      totalVfFlow: globalTotalVfFlow,
      totalInstaFlow: globalTotalInstaFlow,
    }), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });

  } catch (error: any) {
    console.error("[Get Investor Performance] Error:", error);
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 500, 
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } 
    });
  }
});
