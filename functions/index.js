/**
 * Firebase Cloud Function: resetDailyLimits
 * 
 * Runs every day at 01:00 UTC (03:00 Cairo / EET).
 * Zeroes out `inDailyUsed` and `outDailyUsed` on every mobile_numbers record.
 * 
 * SAFETY: This function ONLY writes to inDailyUsed and outDailyUsed.
 * It does NOT touch any balances, limits, totals, or any other fields.
 * The in-app reset logic in app_provider.dart remains as a client-side fallback.
 */

const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

admin.initializeApp();

exports.resetDailyLimits = onSchedule(
  {
    schedule: '1 0 * * *',   // 00:01 Africa/Cairo — DST handled automatically
    timeZone: 'Africa/Cairo',
    region: 'us-central1',
  },
  async (event) => {
    const db = admin.database();
    const ref = db.ref('mobile_numbers');

    try {
      const snapshot = await ref.once('value');
      if (!snapshot.exists()) {
        console.log('[resetDailyLimits] No mobile_numbers found — nothing to reset.');
        return;
      }

      const numbers = snapshot.val();
      const updates = {};
      let count = 0;

      for (const numberId of Object.keys(numbers)) {
        updates[`mobile_numbers/${numberId}/inDailyUsed`]  = 0;
        updates[`mobile_numbers/${numberId}/outDailyUsed`] = 0;
        count++;
      }

      if (count === 0) {
        console.log('[resetDailyLimits] No entries to update.');
        return;
      }

      // Write all resets atomically in a single multi-path update
      await db.ref().update(updates);

      // Write an audit timestamp so the app can confirm the function ran
      await db.ref('system/lastDailyReset').set({
        timestamp: new Date().toISOString(),
        resetCount: count,
        resetBy: 'cloud_function',
      });

      console.log(`[resetDailyLimits] ✅ Reset inDailyUsed + outDailyUsed for ${count} number(s).`);
    } catch (error) {
      console.error('[resetDailyLimits] ❌ Error:', error);
      throw error; // Let Firebase retry on failure
    }
  }
);
