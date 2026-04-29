const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function update() {
  await supabase.from('system_config').upsert({key: 'openingCapital', value: 258000});
  console.log('Updated openingCapital to 258000');
}

update();
