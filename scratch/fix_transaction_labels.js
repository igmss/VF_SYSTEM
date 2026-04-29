const { createClient } = require('@supabase/supabase-js');
const dotenv = require('dotenv');
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function fixHistory() {
  console.log('Fixing transaction history labels...');
  
  const { data: d1, error: e1 } = await supabase.from('transactions').update({ payment_method: 'Vodafone Distribution' }).like('bybit_order_id', 'DIST-%').is('payment_method', null);
  const { data: d2, error: e2 } = await supabase.from('transactions').update({ payment_method: 'Internal VF Transfer (Out)' }).like('bybit_order_id', 'INT-S-%').is('payment_method', null);
  const { data: d3, error: e3 } = await supabase.from('transactions').update({ payment_method: 'Internal VF Transfer (In)' }).like('bybit_order_id', 'INT-D-%').is('payment_method', null);

  if (e1) console.error('Error fixing DIST:', e1);
  if (e2) console.error('Error fixing INT-S:', e2);
  if (e3) console.error('Error fixing INT-D:', e3);

  console.log('Done.');
}

fixHistory();
