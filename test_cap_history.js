const admin = require('firebase-admin');
const fs = require('fs');

const serviceAccount = JSON.parse(fs.readFileSync('d:\\New folder\\vodafone_system\\functions\\vodatracking-firebase-adminsdk-r19g4-0d75c58add.json'));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://vodatracking-default-rtdb.asia-southeast1.firebasedatabase.app/'
});

const db = admin.database();

async function run() {
  const cap = await db.ref('system_config/openingCapitalHistory').once('value');
  console.log('Capital History: ', cap.val());
  process.exit(0);
}

run();
