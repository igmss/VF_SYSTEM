const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const supabaseUrl = process.env.SUPABASE_URL;
const anonKey = process.env.SUPABASE_ANON_KEY;

async function testBybitEdgeFunction() {
  console.log("Calling bybit-test Edge Function...");
  console.log(`URL: ${supabaseUrl}/functions/v1/bybit-test`);

  try {
    const response = await fetch(`${supabaseUrl}/functions/v1/bybit-test`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${anonKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({})
    });

    const result = await response.json();
    console.log("Response from Edge Function:");
    console.log(JSON.stringify(result, null, 2));

    if (result.success) {
      console.log("\n✅ SUCCESS: Tokyo Edge Function can reach Bybit API!");
    } else {
      console.log("\n❌ FAILED: Edge Function reached, but Bybit API call failed.");
    }
  } catch (error) {
    console.error("\n❌ ERROR: Could not call Edge Function. Is it deployed?");
    console.error(error.message);
  }
}

testBybitEdgeFunction();
