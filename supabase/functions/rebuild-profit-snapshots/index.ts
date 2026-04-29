import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createServiceClient } from "../_shared/supabaseClient.ts";
import { verifyAuth, getCallerRole, parseBody, asNumber } from "../_shared/helpers.ts";
import { 
  _ensureSystemProfitSnapshots,
  _buildInvestorSnapshotForDate,
  _buildPartnerSnapshotForDate,
  _buildProfitDistributionContext,
  formatDateKey,
  getDateKeysForRange,
  DbData
} from "../_shared/profitEngine.ts";


console.log("Rebuild-Profit-Snapshots function started");

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });
  }

  try {
    const supabase = createServiceClient();
    
    // 1. Verify Auth & Admin Role
    const { uid } = await verifyAuth(req, supabase);
    const role = await getCallerRole(uid, supabase);
    if (role !== 'ADMIN' && uid !== 'SERVICE_ROLE') {
      return new Response(JSON.stringify({ error: "Admin access required" }), { status: 403 });
    }

    // 2. Parse Request
    const { startDate, endDate, resetPaidFlags = false } = await parseBody(req);
    if (!startDate || !endDate) {
      return new Response(JSON.stringify({ error: "startDate and endDate are required" }), { status: 400 });
    }

    // 3. Fetch All Required Data for the Engine
    const [
      configRes,
      ledgerRes,
      banksRes,
      usdRes,
      retailersRes,
      collectorsRes,
      loansRes,
      investorsRes,
      partnersRes,
      numbersRes
    ] = await Promise.all([
      supabase.from("system_config").select("value").eq("key", "openingCapital").single(),
      supabase.from("financial_ledger").select("*"),
      supabase.from("bank_accounts").select("*"),
      supabase.from("usd_exchange").select("*").eq("id", 1).single(),
      supabase.from("retailers").select("*"),
      supabase.from("collectors").select("*"),
      supabase.from("loans").select("*"),
      supabase.from("investors").select("*"),
      supabase.from("partners").select("*"),
      supabase.from("mobile_numbers").select("*")
    ]);

    const dbData: DbData = {
      openingCapital: asNumber(configRes.data?.value || 300000),
      ledger: ledgerRes.data || [],
      banks: banksRes.data || [],
      usdExchange: usdRes.data || null,
      retailers: retailersRes.data || [],
      collectors: collectorsRes.data || [],
      loans: loansRes.data || [],
      investors: investorsRes.data || [],
      mobileNumbers: numbersRes.data || []
    };

    const totalDistributions = 0;

    // 4. Calculate System Profit Snapshots first
    const diffInMs = new Date(endDate).getTime() - new Date(startDate).getTime();
    const workingDays = Math.ceil(diffInMs / (1000 * 60 * 60 * 24)) + 1;
    
    const systemSnapshotsMap = await _ensureSystemProfitSnapshots(supabase, endDate, workingDays, dbData, totalDistributions);
    const dateKeys = Object.keys(systemSnapshotsMap).sort();

    // 5. Calculate Investor and Partner Snapshots
    const activeInvestors = dbData.investors
      .filter(i => i.status === 'active')
      .sort((a, b) => formatDateKey(a.investment_date).localeCompare(formatDateKey(b.investment_date)));

    const distributionContext = _buildProfitDistributionContext(dateKeys, systemSnapshotsMap, dbData, totalDistributions);

    const investorSnapshots: any[] = [];
    const partnerSnapshots: any[] = [];

    dateKeys.forEach(dayKey => {
      const systemSnapshot = systemSnapshotsMap[dayKey];
      let dailyInvestorProfitTotal = 0;
      let precedingCapital = 0;

      activeInvestors.forEach((investor, index) => {
        if (dayKey >= formatDateKey(investor.investment_date)) {
          // Calculate preceding capital for the waterfall
          precedingCapital = 0;
          for (let j = 0; j < index; j++) {
            precedingCapital += asNumber(activeInvestors[j].invested_amount);
          }

          const invSnap = _buildInvestorSnapshotForDate(
            investor,
            systemSnapshot,
            precedingCapital,
            dbData.openingCapital
          );
          investorSnapshots.push(invSnap);
          dailyInvestorProfitTotal += invSnap.investor_profit;
        }
      });

      // Calculate partner snapshots for this day
      (partnersRes.data || []).forEach(partner => {
        if (partner.status === 'active') {
          const partSnap = _buildPartnerSnapshotForDate(
            partner,
            systemSnapshot,
            dailyInvestorProfitTotal,
            null,
            distributionContext.allocationRatio
          );
          partnerSnapshots.push(partSnap);
        }
      });
    });

    // 6. Bulk Upsert Snapshots
    if (investorSnapshots.length > 0) {
      await supabase.from("investor_profit_snapshots").upsert(investorSnapshots);
    }
    if (partnerSnapshots.length > 0) {
      await supabase.from("partner_profit_snapshots").upsert(partnerSnapshots);
    }

    return new Response(JSON.stringify({ 
      success: true, 
      workingDays, 
      snapshotsCount: dateKeys.length,
      investorSnapshotsCount: investorSnapshots.length,
      partnerSnapshotsCount: partnerSnapshots.length
    }), { 
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } 
    });

  } catch (error: any) {
    console.error("[Rebuild Profit Snapshots] Error:", error);
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 500, 
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } 
    });
  }
});
