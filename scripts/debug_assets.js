const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function check() {
  console.log('Calling get-partner-performance...');
  const { data, error } = await supabase.functions.invoke('get-partner-performance');
  if (error) {
    console.error('Error:', error);
    return;
  }
  
  console.log('--- Assets Summary (Health) ---');
  console.log(JSON.stringify(data.assetsSummary, null, 2));
  
  const health = data.assetsSummary;
  const manualSum = (health.bankBalance || 0) + 
                    (health.vfNumberBalance || 0) + 
                    (health.retailerDebt || 0) + 
                    (health.retailerInstaDebt || 0) + 
                    (health.collectorCash || 0) + 
                    (health.usdExchangeEgp || 0);
  
  console.log('\n--- Manual Verification ---');
  console.log('Bank:', health.bankBalance);
  console.log('SIMs:', health.vfNumberBalance);
  console.log('Retailer Debt:', health.retailerDebt);
  console.log('Retailer Insta Debt:', health.retailerInstaDebt);
  console.log('Collector Cash:', health.collectorCash);
  console.log('USD EGP:', health.usdExchangeEgp);
  console.log('SUM:', manualSum);
  console.log('\n--- System Config ---');
  const { data: config } = await supabase.from('system_config').select('*');
  console.log(JSON.stringify(config, null, 2));
}

check();
