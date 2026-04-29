require('dotenv').config();
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const url = process.env.SUPABASE_URL;

async function checkColumn() {
    const sql = `SELECT column_name, generation_expression 
                 FROM information_schema.columns 
                 WHERE table_name = 'retailers' AND (column_name = 'pending_debt' OR column_name = 'insta_pay_pending_debt');`;
    
    // Note: execute_sql is a custom RPC I've seen in some Supabase setups, 
    // but if it doesn't exist, I can just query the rest api if information_schema is exposed.
    // Actually, I can just check the schema.sql if I have it.
    
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
        console.log(await res.json());
    } else {
        console.log('RPC execute_sql not found or error:', res.status, await r.text());
    }
}
checkColumn();
