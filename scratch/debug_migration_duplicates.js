const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function debugTables() {
  console.log('--- COLLECTORS ---');
  const { data: collectors } = await supabase.from('collectors').select('*');
  console.table(collectors.map(c => ({ id: c.id, name: c.name, cash: c.cash_on_hand })));

  console.log('\n--- USERS ---');
  const { data: users } = await supabase.from('users').select('*');
  console.table(users.map(u => ({ id: u.id, email: u.email, firebase_uid: u.firebase_uid, role: u.role })));
}

debugTables();
