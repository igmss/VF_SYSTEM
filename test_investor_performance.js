const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);

async function test() {
  console.log("Invoking get-investor-performance...");
  try {
    const { data, error } = await supabase.functions.invoke('get-investor-performance');
    if (error) {
      console.error("Function Error:", error);
    } else {
      console.log("Function Result:", JSON.stringify(data, null, 2));
    }
  } catch (err) {
    console.error("Fetch Error:", err);
  }
}

test();
