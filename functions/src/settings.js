const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { asNumber, getCallerRole, requireFinanceRole } = require('./shared/helpers');

const REGION = 'asia-east1';

exports.setBybitCredentials = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') {
    throw new HttpsError('permission-denied', 'Only admins can manage credentials.');
  }

  const apiKey = request.data?.apiKey?.toString().trim();
  const apiSecret = request.data?.apiSecret?.toString().trim();
  if (!apiKey || !apiSecret) {
    throw new HttpsError('invalid-argument', 'API credentials are required.');
  }

  const nowIso = new Date().toISOString();
  await admin.database().ref().update({
    'system/api_credentials/bybit/apiKey': apiKey,
    'system/api_credentials/bybit/apiSecret': apiSecret,
    'system/api_credentials/bybit/updatedAt': nowIso,
    'system/api_credentials/bybit_metadata/configured': true,
    'system/api_credentials/bybit_metadata/updatedAt': nowIso,
  });

  return { configured: true, updatedAt: nowIso };
});

exports.clearBybitCredentials = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  const role = await getCallerRole(uid);
  if (role !== 'ADMIN') {
    throw new HttpsError('permission-denied', 'Only admins can manage credentials.');
  }

  const nowIso = new Date().toISOString();
  await admin.database().ref().update({
    'system/api_credentials/bybit': null,
    'system/api_credentials/bybit_metadata/configured': false,
    'system/api_credentials/bybit_metadata/updatedAt': nowIso,
  });

  return { configured: false, updatedAt: nowIso };
});

exports.setCollectorVfDepositFeePer1000 = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Login required');
  await requireFinanceRole(uid);

  const feePer1000 = asNumber(request.data?.feePer1000);
  if (feePer1000 < 0) {
    throw new HttpsError('invalid-argument', 'Fee per 1000 must be zero or greater.');
  }

  const nowIso = new Date().toISOString();
  await admin.database().ref().update({
    'system/operation_settings/collectorVfDepositFeePer1000': feePer1000,
    'system/operation_settings/updatedAt': nowIso,
  });

  return { feePer1000, updatedAt: nowIso };
});
