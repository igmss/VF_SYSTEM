const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

async function run() {
  console.log("Checking users in Supabase...");
  
  // 1. Fetch all users from public.users
  const { data: publicUsers, error: dbError } = await supabase.from('users').select('*');
  if (dbError) {
    console.error("Error reading public.users:", dbError);
    return;
  }
  
  console.log(`Found ${publicUsers.length} users in public.users table.`);
  
  // 2. Fetch all users from auth.users (requires service role)
  const { data: authData, error: authError } = await supabase.auth.admin.listUsers();
  if (authError) {
    console.error("Error reading auth.users:", authError);
    return;
  }
  
  const authUsers = authData.users;
  console.log(`Found ${authUsers.length} users in auth.users.`);
  
  // Compare and show
  for (const authUser of authUsers) {
    console.log(`\n--- Auth User: ${authUser.email} ---`);
    console.log(`Auth ID: ${authUser.id}`);
    
    // Find matching public user by ID or firebase_uid or email
    const matchedById = publicUsers.find(u => u.id === authUser.id);
    const matchedByFirebaseUid = publicUsers.find(u => u.firebase_uid === authUser.user_metadata?.firebase_uid);
    const matchedByEmail = publicUsers.find(u => u.email === authUser.email);
    
    if (matchedById) {
      console.log(`✅ MATCHED in public.users by ID. Role: ${matchedById.role}, IsActive: ${matchedById.is_active}`);
    } else if (matchedByFirebaseUid) {
      console.log(`⚠️ Mismatched ID, but matched by firebase_uid! public.users.id is ${matchedByFirebaseUid.id}`);
      // Let's fix it automatically!
      console.log(`Attempting to auto-fix ID mismatch...`);
      const {error: fixError} = await supabase.from('users').update({id: authUser.id}).eq('firebase_uid', matchedByFirebaseUid.firebase_uid);
      if(fixError) console.log("Fix error:", fixError); else console.log("Fix successful!");
    } else if (matchedByEmail) {
      console.log(`⚠️ Mismatched ID, but matched by email! public.users.id is ${matchedByEmail.id}`);
      console.log(`Attempting to auto-fix ID mismatch...`);
      const {error: fixError} = await supabase.from('users').update({id: authUser.id}).eq('email', matchedByEmail.email);
      if(fixError) console.log("Fix error:", fixError); else console.log("Fix successful!");
    } else {
      console.log(`❌ NOT FOUND in public.users table!`);
    }
  }
}

run();
