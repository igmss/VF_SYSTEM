const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json'); // I'll assume I can't find this, I'll use the default app if possible

if (admin.apps.length === 0) {
  admin.initializeApp();
}

async function migrateFlow() {
  const db = admin.database();
  const ledgerSnap = await db.ref('financial_ledger').once('value');
  const flowByDate = {};

  ledgerSnap.forEach((child) => {
    const tx = child.val();
    if (tx.type === 'DISTRIBUTE_VFCASH' || tx.type === 'DISTRIBUTE_INSTAPAY') {
      const date = new Date(tx.timestamp).toISOString().split('T')[0];
      if (!flowByDate[date]) flowByDate[date] = { vf: 0, insta: 0 };
      
      const amount = parseFloat(tx.amount) || 0;
      if (tx.type === 'DISTRIBUTE_VFCASH') {
        flowByDate[date].vf += amount;
      } else {
        flowByDate[date].insta += amount;
      }
    }
  });

  console.log('Processed dates:', Object.keys(flowByDate).length);
  const updates = {};
  for (const date in flowByDate) {
    updates[`summary/daily_flow/${date}/vf`] = flowByDate[date].vf;
    updates[`summary/daily_flow/${date}/insta`] = flowByDate[date].insta;
  }

  await db.ref().update(updates);
  console.log('Migration complete.');
}

migrateFlow().then(() => process.exit(0)).catch(err => { console.error(err); process.exit(1); });
