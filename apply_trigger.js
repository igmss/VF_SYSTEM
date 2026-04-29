require('dotenv').config();
const fs = require('fs');
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const url = process.env.SUPABASE_URL;

async function runMigration() {
    const sql = fs.readFileSync('supabase/migrations/006_retailer_sync_trigger.sql', 'utf8');
    
    // We try to use a standard Supabase RPC if it exists, 
    // but often projects don't have a generic execute_sql.
    // Let's try to find if there's one.
    
    const res = await fetch(url + '/rest/v1/rpc/execute_sql', {
        method: 'POST',
        headers: {
            'apikey': key,
            'Authorization': 'Bearer ' + key,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ query: sql })
    });
    
    if (res.status === 200) {
        console.log('Migration applied successfully.');
    } else {
        console.log('Failed to apply migration via RPC:', res.status, await res.text());
        console.log('Please apply supabase/migrations/006_retailer_sync_trigger.sql manually in the SQL Editor.');
    }
}
runMigration();
