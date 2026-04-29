const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseServiceKey) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey);

function asNumber(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

async function run() {
  const outDir = __dirname;

  const { data: investors, error: invErr } = await supabase
    .from('investors')
    .select('id,name,total_profit_paid,status')
    .eq('status', 'active')
    .order('investment_date', { ascending: true });
  if (invErr) throw invErr;

  const { data: partners, error: partErr } = await supabase
    .from('partners')
    .select('id,name,total_profit_paid,status')
    .eq('status', 'active')
    .order('name', { ascending: true });
  if (partErr) throw partErr;

  const investorPerfResp = await supabase.functions.invoke('get-investor-performance', { body: {} });
  if (investorPerfResp.error) throw investorPerfResp.error;
  const investorPerf = investorPerfResp.data || {};

  const partnerPerfResp = await supabase.functions.invoke('get-partner-performance', { body: {} });
  if (partnerPerfResp.error) throw partnerPerfResp.error;
  const partnerPerf = partnerPerfResp.data || {};

  const investorIds = (investors || []).map((i) => i.id);
  const partnerIds = (partners || []).map((p) => p.id);

  const investorDetails = {};
  for (const investorId of investorIds) {
    const resp = await supabase.functions.invoke('get-investor-performance', { body: { investor_id: investorId } });
    if (resp.error) throw resp.error;
    investorDetails[investorId] = resp.data || {};
  }

  const { data: investorSnaps, error: invSnapErr } = await supabase
    .from('investor_profit_snapshots')
    .select('investor_id,date_key,investor_profit,vf_investor_profit,insta_investor_profit,is_paid,paid_at')
    .in('investor_id', investorIds.length ? investorIds : ['00000000-0000-0000-0000-000000000000'])
    .order('date_key', { ascending: false });
  if (invSnapErr) throw invSnapErr;

  const { data: partnerSnaps, error: partSnapErr } = await supabase
    .from('partner_profit_snapshots')
    .select('partner_id,date_key,partner_profit,is_paid,paid_at')
    .in('partner_id', partnerIds.length ? partnerIds : ['00000000-0000-0000-0000-000000000000'])
    .order('date_key', { ascending: false });
  if (partSnapErr) throw partSnapErr;

  const invSnapsByInvestor = {};
  (investorSnaps || []).forEach((s) => {
    if (!invSnapsByInvestor[s.investor_id]) invSnapsByInvestor[s.investor_id] = [];
    invSnapsByInvestor[s.investor_id].push(s);
  });

  const partSnapsByPartner = {};
  (partnerSnaps || []).forEach((s) => {
    if (!partSnapsByPartner[s.partner_id]) partSnapsByPartner[s.partner_id] = [];
    partSnapsByPartner[s.partner_id].push(s);
  });

  const investorsOut = (investors || []).map((inv) => {
    const snaps = invSnapsByInvestor[inv.id] || [];
    const totalEarned = snaps.reduce((sum, s) => sum + asNumber(s.investor_profit), 0);
    const totalPaid = asNumber(inv.total_profit_paid);
    return {
      investor_id: inv.id,
      name: inv.name,
      totalEarned,
      totalPaid,
      payableBalance: Math.max(0, totalEarned - totalPaid),
      history: snaps,
    };
  });

  const partnersOut = (partners || []).map((p) => {
    const snaps = partSnapsByPartner[p.id] || [];
    const totalEarned = snaps.reduce((sum, s) => sum + asNumber(s.partner_profit), 0);
    const totalPaid = asNumber(p.total_profit_paid);
    return {
      partner_id: p.id,
      name: p.name,
      totalEarned,
      totalPaid,
      payableBalance: Math.max(0, totalEarned - totalPaid),
      history: snaps,
    };
  });

  const output = {
    generatedAt: new Date().toISOString(),
    edge: {
      investors: investorPerf,
      partners: partnerPerf,
      investorDetails
    },
    snapshots: {
      investors: investorsOut,
      partners: partnersOut,
    },
  };

  const outPath = path.join(outDir, `profit_history_extract_${Date.now()}.json`);
  fs.writeFileSync(outPath, JSON.stringify(output, null, 2), 'utf8');

  console.log(JSON.stringify({
    outputFile: outPath,
    investors: {
      count: investorsOut.length,
      totalEarned: investorsOut.reduce((s, i) => s + asNumber(i.totalEarned), 0),
      totalPaid: investorsOut.reduce((s, i) => s + asNumber(i.totalPaid), 0),
      totalPayable: investorsOut.reduce((s, i) => s + asNumber(i.payableBalance), 0),
    },
    partners: {
      count: partnersOut.length,
      totalEarned: partnersOut.reduce((s, p) => s + asNumber(p.totalEarned), 0),
      totalPaid: partnersOut.reduce((s, p) => s + asNumber(p.totalPaid), 0),
      totalPayable: partnersOut.reduce((s, p) => s + asNumber(p.payableBalance), 0),
    },
  }, null, 2));
}

run().catch((e) => {
  console.error(e?.message || e);
  process.exit(1);
});
