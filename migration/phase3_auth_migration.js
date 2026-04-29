const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env");
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

async function run() {
  console.log("Starting Phase 3 Auth Migration...");
  
  const usersFile = path.join(__dirname, '../users.json');
  if (!fs.existsSync(usersFile)) {
    console.error(`users.json not found at ${usersFile}. Please run 'firebase auth:export users.json --format=json' first.`);
    process.exit(1);
  }

  const { users } = JSON.parse(fs.readFileSync(usersFile, 'utf-8'));
  console.log(`Found ${users.length} users in Firebase export.`);

  for (const firebaseUser of users) {
    const { localId, email, displayName, disabled } = firebaseUser;
    console.log(`Processing user: ${email} (${localId})`);

    try {
      // 1. Create user in Supabase Auth
      // Use a generic temporary password or generate one
      const tempPassword = 'TempPassword123!@#';
      
      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email: email,
        password: tempPassword,
        email_confirm: true, // Auto-confirm email
        user_metadata: {
          name: displayName || '',
          firebase_uid: localId
        }
      });

      let supabaseUid;
      if (authError) {
        if (authError.code === 'email_exists' || authError.status === 422) {
          console.log(`User ${email} already exists in Supabase Auth. Fetching UUID...`);
          const { data: { users: existingUsers } } = await supabase.auth.admin.listUsers();
          const existingUser = existingUsers.find(u => u.email === email);
          if (existingUser) {
            supabaseUid = existingUser.id;
          } else {
            console.error(`Could not find existing user ${email}. Skipping.`);
            continue;
          }
        } else {
          console.error(`Error creating user ${email}:`, authError);
          continue;
        }
      } else {
        supabaseUid = authData.user.id;
      }

      console.log(`Supabase Auth created/found. UUID: ${supabaseUid}`);

      // 2. Populate uid_mapping table
      const { error: mappingError } = await supabase.from('uid_mapping').upsert({
        firebase_uid: localId,
        supabase_uid: supabaseUid
      });
      if (mappingError) {
        console.error(`Error updating uid_mapping for ${email}:`, mappingError);
      } else {
        console.log(`uid_mapping populated.`);
      }

      // 3. Update 'users' table 
      // In Phase 2, we created the rows but their id is a random UUID.
      // We should update the id to match supabaseUid, but wait, id is PRIMARY KEY. 
      // Supabase Postgres allows updating PK if there are no strict FKs.
      // But it's easier to just update the row where firebase_uid matches.
      const { error: usersError } = await supabase.from('users')
        .update({ id: supabaseUid })
        .eq('firebase_uid', localId);
      
      if (usersError) {
        console.error(`Error updating 'users' table id for ${email}:`, usersError);
      } else {
        console.log(`users table updated with new UUID.`);
      }

      // 4. Update 'collectors' table
      const { error: collectorsError } = await supabase.from('collectors')
        .update({ supabase_uid: supabaseUid })
        .eq('id', localId);
      
      if (collectorsError) {
        console.error(`Error updating 'collectors' table for ${email}:`, collectorsError);
      } else {
        console.log(`collectors table updated.`);
      }
      
      console.log(`----------------------------------------`);
    } catch (err) {
      console.error(`Unexpected error processing ${email}:`, err);
    }
  }

  console.log("Phase 3 Auth Migration Completed!");
}

run();
