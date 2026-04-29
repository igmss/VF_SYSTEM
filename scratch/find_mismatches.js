const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();
const s = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function main() {
  const { data: users } = await s.from('users').select('*');
  const { data: collectors } = await s.from('collectors').select('*');

  console.log('--- Mismatches ---');
  for (const coll of collectors) {
    const user = users.find(u => u.email === coll.email);
    if (!user) {
      console.log(`Collector ${coll.name} (${coll.email}) has NO user record.`);
      continue;
    }
    const targetUid = user.firebase_uid || user.id;
    if (coll.uid !== targetUid) {
      console.log(`Collector ${coll.name}: Coll UID=${coll.uid}, User TargetUID=${targetUid}`);
    }
  }
}
main();
