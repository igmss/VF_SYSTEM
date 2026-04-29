const fs = require('fs');
const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();
const s = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function main() {
  const sims = ['01020740962', '01064495331', '01080623453', '01061492827', '01065377986', '01080453953'];

  console.log('\nComparing Transactions SUM vs current in_total_used vs Firebase export:\n');
  console.log('Phone         | TX side=1 sum | SB in_total  | FB in_total  | TX=SB? | SB=FB?');
  console.log('--------------|---------------|--------------|--------------|--------|--------');

  // Load Firebase export
  const data = JSON.parse(fs.readFileSync('vodatracking-default-rtdb-export - 2026-04-29T000543.914.json', 'utf8'));
  const fbMap = {};
  Object.values(data.mobile_numbers).forEach(n => { fbMap[n.phoneNumber] = n.inTotalUsed || 0; });

  for (const phone of sims) {
    const { data: txs } = await s.from('transactions')
      .select('amount, side, status')
      .eq('phone_number', phone);

    const txSum = (txs || []).filter(t => t.side === 1 && t.status === 'completed').reduce((a, t) => a + t.amount, 0);

    const { data: sim } = await s.from('mobile_numbers').select('in_total_used').eq('phone_number', phone).single();
    const sbIn = sim?.in_total_used || 0;
    const fbIn = fbMap[phone] || 0;

    const txMatchSb = Math.abs(txSum - sbIn) < 0.01;
    const sbMatchFb = Math.abs(sbIn - fbIn) < 0.01;

    console.log(
      phone.padEnd(14) + '| ' +
      txSum.toFixed(2).padStart(13) + ' | ' +
      sbIn.toFixed(2).padStart(12) + ' | ' +
      fbIn.toFixed(2).padStart(12) + ' | ' +
      (txMatchSb ? '  ✅  ' : '  ❌  ') + ' | ' +
      (sbMatchFb ? '  ✅' : '  ❌ CHANGED')
    );
  }

  // Also check: did recalculate_mobile_usage RPC exist and get called?
  console.log('\nChecking what recalculate_mobile_usage would produce:');
  const { data: allLedger } = await s.from('financial_ledger').select('to_id, amount');
  const { data: allSims } = await s.from('mobile_numbers').select('id, phone_number');
  const idToPhone = {};
  allSims.forEach(n => { idToPhone[n.id] = n.phone_number; });

  const ledgerSums = {};
  allLedger.forEach(e => {
    if (e.to_id) ledgerSums[e.to_id] = (ledgerSums[e.to_id] || 0) + e.amount;
  });

  console.log('Phone         | Ledger sum   | Current SB   | Firebase     | Ledger=FB?');
  console.log('--------------|--------------|--------------|--------------|----------');
  for (const sim of allSims) {
    const lSum = ledgerSums[sim.id] || 0;
    const { data: simRow } = await s.from('mobile_numbers').select('in_total_used').eq('id', sim.id).single();
    const sb = simRow?.in_total_used || 0;
    const fb = fbMap[sim.phone_number] || 0;
    const match = Math.abs(lSum - fb) < 0.01;
    console.log(
      sim.phone_number.padEnd(14) + '| ' +
      lSum.toFixed(2).padStart(12) + ' | ' +
      sb.toFixed(2).padStart(12) + ' | ' +
      fb.toFixed(2).padStart(12) + ' | ' +
      (match ? '  ✅' : '  ❌ diff=' + (lSum - fb).toFixed(2))
    );
  }
}
main().catch(console.error);
