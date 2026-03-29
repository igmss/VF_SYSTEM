const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const REGION = 'asia-east1';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

exports.createUserAccount = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Login required');
  }

  const callerSnap = await admin.database().ref(`users/${uid}`).once('value');
  const caller = callerSnap.val();
  if (!caller || caller.role !== 'ADMIN') {
    throw new HttpsError('permission-denied', 'Only admins can create users.');
  }

  const email = request.data?.email?.toString().trim().toLowerCase();
  const password = request.data?.password?.toString() || '';
  const name = request.data?.name?.toString().trim();
  const role = request.data?.role?.toString().trim().toUpperCase();
  const retailerId = request.data?.retailerId?.toString().trim() || '';
  const allowedRoles = new Set(['ADMIN', 'FINANCE', 'COLLECTOR', 'RETAILER']);

  if (!email || !name || !allowedRoles.has(role)) {
    throw new HttpsError('invalid-argument', 'Invalid user data.');
  }
  if (password.length < 6) {
    throw new HttpsError('invalid-argument', 'Password must be at least 6 characters.');
  }
  if (role === 'RETAILER' && !retailerId) {
    throw new HttpsError('invalid-argument', 'Retailer profile is required for retailer accounts.');
  }

  if (role === 'RETAILER') {
    const retailerSnap = await admin.database().ref(`retailers/${retailerId}`).once('value');
    if (!retailerSnap.exists()) {
      throw new HttpsError('not-found', 'That retailer record does not exist.');
    }
  }

  let userRecord;
  try {
    userRecord = await admin.auth().createUser({
      email,
      password,
      displayName: name,
    });
  } catch (error) {
    if (error?.code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'This email is already in use.');
    }
    throw new HttpsError('internal', error.message || 'Unable to create auth user.');
  }

  const nowIso = new Date().toISOString();
  const userPayload = {
    uid: userRecord.uid,
    email,
    name,
    role,
    isActive: true,
    createdAt: nowIso,
  };
  if (role === 'RETAILER') {
    userPayload.retailerId = retailerId;
  }

  const updates = {
    [`users/${userRecord.uid}`]: userPayload,
  };

  if (role === 'COLLECTOR') {
    updates[`collectors/${userRecord.uid}`] = {
      id: userRecord.uid,
      name,
      phone: '',
      email,
      uid: userRecord.uid,
      cashOnHand: 0.0,
      cashLimit: 50000.0,
      totalCollected: 0.0,
      totalDeposited: 0.0,
      isActive: true,
      createdAt: nowIso,
      lastUpdatedAt: nowIso,
    };
  }

  try {
    await admin.database().ref().update(updates);
    return { uid: userRecord.uid };
  } catch (error) {
    await admin.auth().deleteUser(userRecord.uid).catch(() => {});
    throw new HttpsError('internal', error.message || 'Unable to persist user profile.');
  }
});
