const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();
const s = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function main() {
  console.log('Fetching auth users...');
  const { data: { users: authUsers }, error: authError } = await s.auth.admin.listUsers();
  if (authError) throw authError;

  console.log('Fetching database users...');
  const { data: dbUsers } = await s.from('users').select('*');

  console.log('Fetching collectors...');
  const { data: collectors } = await s.from('collectors').select('*');

  for (const authUser of authUsers) {
    const dbUser = dbUsers.find(u => u.email.toLowerCase() === authUser.email.toLowerCase());
    if (dbUser) {
      if (dbUser.id !== authUser.id) {
        console.log(`Syncing User ${dbUser.email}: DB ID ${dbUser.id} -> Auth ID ${authUser.id}`);
        
        // 1. Update user record (this might fail if ID is PK and referenced)
        // Better to update where email matches
        const { error: updateError } = await s.from('users')
          .update({ id: authUser.id, firebase_uid: authUser.id })
          .eq('email', authUser.email);
        
        if (updateError) console.error(`Error updating user ${dbUser.email}:`, updateError);
      } else {
        // Even if ID matches, ensure firebase_uid is set to the same UUID for consistency in AuthService
        await s.from('users').update({ firebase_uid: authUser.id }).eq('id', authUser.id);
      }

      // 2. Sync Collector
      const collector = collectors.find(c => c.email.toLowerCase() === authUser.email.toLowerCase());
      if (collector) {
        if (collector.uid !== authUser.id) {
          console.log(`Syncing Collector ${collector.name}: Old UID ${collector.uid} -> New UID ${authUser.id}`);
          
          // Update retailers who were assigned to this collector
          const { error: retError } = await s.from('retailers')
            .update({ assigned_collector_id: authUser.id })
            .eq('assigned_collector_id', collector.uid);
          if (retError) console.error(`Error updating retailers for ${collector.name}:`, retError);

          // Update ledger entries
          await s.from('financial_ledger').update({ from_id: authUser.id }).eq('from_id', collector.uid);
          await s.from('financial_ledger').update({ to_id: authUser.id }).eq('to_id', collector.uid);
          await s.from('financial_ledger').update({ created_by_uid: authUser.id }).eq('created_by_uid', collector.uid);

          // Finally update the collector record itself
          const { error: collError } = await s.from('collectors')
            .update({ uid: authUser.id, id: authUser.id }) // Also change ID to match for simplicity? 
            // Wait, if I change collector.id, I must have updated all references.
            .eq('email', authUser.email);
          if (collError) console.error(`Error updating collector ${collector.name}:`, collError);
        }
      }
    }
  }
  console.log('Sync complete.');
}

main().catch(console.error);
