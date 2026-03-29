const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const REGION = 'asia-east1';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

async function getCallerRole(uid) {
  const snap = await admin.database().ref(`users/${uid}`).once('value');
  return snap.val()?.role || null;
}

function defaultLast24hMs() {
  const endMs = Date.now();
  const startMs = endMs - 24 * 60 * 60 * 1000;
  return { startMs, endMs };
}

/**
 * Retailer portal: snapshot of retailer node + ledger lines involving this retailer for a day range.
 */
exports.getRetailerPortalData = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');

  const role = await getCallerRole(uid);
  if (!['RETAILER', 'ADMIN', 'FINANCE'].includes(role)) {
    throw new HttpsError('permission-denied', 'Unauthorized');
  }

  let retailerId = request.data?.retailerId?.toString().trim() || '';
  const userSnap = await admin.database().ref(`users/${uid}`).once('value');
  const user = userSnap.val();

  if (role === 'RETAILER') {
    retailerId = user?.retailerId?.toString() || '';
    if (!retailerId) {
      throw new HttpsError('failed-precondition', 'Your account is not linked to a retailer profile.');
    }
  } else if (!retailerId) {
    throw new HttpsError('invalid-argument', 'retailerId is required.');
  }

  if (role === 'RETAILER' && user?.retailerId?.toString() !== retailerId) {
    throw new HttpsError('permission-denied', 'Unauthorized');
  }

  const def = defaultLast24hMs();
  const startMs = request.data?.startMs != null
    ? parseInt(request.data.startMs, 10)
    : def.startMs;
  const endMs = request.data?.endMs != null
    ? parseInt(request.data.endMs, 10)
    : def.endMs;

  const db = admin.database();
  const [retailerSnap, ledgerSnap] = await Promise.all([
    db.ref(`retailers/${retailerId}`).once('value'),
    db.ref('financial_ledger')
      .orderByChild('timestamp')
      .startAt(startMs)
      .endAt(endMs)
      .once('value'),
  ]);

  if (!retailerSnap.exists()) {
    throw new HttpsError('not-found', 'Retailer not found.');
  }

  const activity = [];
  if (ledgerSnap.exists()) {
    ledgerSnap.forEach((child) => {
      const v = child.val();
      const fid = v.fromId != null ? v.fromId.toString() : '';
      const tid = v.toId != null ? v.toId.toString() : '';
      if (fid === retailerId || tid === retailerId) {
        activity.push({
          key: child.key,
          ...v,
        });
      }
      return false;
    });
  }

  activity.sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));

  return {
    retailer: retailerSnap.val(),
    retailerId,
    activity,
    range: { startMs, endMs },
  };
});
