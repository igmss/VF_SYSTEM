const admin = require('./node_modules/firebase-admin');
const fs = require('fs');

const serviceAccount = JSON.parse(fs.readFileSync('vodatracking-firebase-adminsdk-r19g4-0d75c58add.json'));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://vodatracking-default-rtdb.asia-southeast1.firebasedatabase.app/'
});

const db = admin.database();

async function run() {
  await db.ref('system_config/openingCapitalHistory').remove();
  console.log('Capital History wiped. The system will now use 180k natively across all history.');
  process.exit(0);
}

run();
