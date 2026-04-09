const { onValueCreated } = require('firebase-functions/v2/database');
const admin = require('firebase-admin');

// Helper to safely parse numbers
function asNumber(value) {
  if (value == null) return 0;
  if (typeof value === 'number') return value;
  const parsed = parseFloat(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

exports.processDailyAggregates = onValueCreated(
  { ref: 'financial_ledger/{transactionId}', region: 'asia-east1' },
  async (event) => {
    const transaction = event.data.val();
    if (!transaction) return;

    const { type, amount, createdByUid, timestamp } = transaction;
    const numAmount = asNumber(amount);
    if (numAmount <= 0) return;

    const db = admin.database();

    // Convert timestamp to YYYY/MM/DD in Cairo timezone ideally.
    // For simplicity we use JS local time or UTC. We will use UTC to avoid server timezone inconsistencies.
    // Given the prompt didn't specify timezone, but previously we used Africa/Cairo, let's format it properly.
    const date = new Date(timestamp || Date.now());

    // We use a simple formatter to get YYYY/MM/DD in Cairo time.
    const options = { timeZone: 'Africa/Cairo', year: 'numeric', month: '2-digit', day: '2-digit' };
    const parts = new Intl.DateTimeFormat('en-GB', options).formatToParts(date);
    const year = parts.find(p => p.type === 'year').value;
    const month = parts.find(p => p.type === 'month').value;
    const day = parts.find(p => p.type === 'day').value;

    const datePath = `${year}/${month}/${day}`;

    // We need to map FlowType to aggregate fields
    let collectionsDelta = 0;
    let expensesDelta = 0;
    let profitDelta = 0;

    switch (type) {
      case 'COLLECT_CASH':
      case 'COLLECT_INSTAPAY_CASH':
        collectionsDelta = numAmount;
        break;
      case 'GENERAL_EXPENSE':
      case 'EXPENSE_VFCASH_FEE':
      case 'EXPENSE_INSTAPAY_FEE':
        expensesDelta = numAmount;
        break;
      case 'VFCASH_RETAIL_PROFIT':
      case 'INSTAPAY_DIST_PROFIT':
        profitDelta = numAmount;
        break;
      default:
        // Other types do not affect these specific aggregates
        return;
    }

    const dailyStatsRef = db.ref(`daily_stats/${datePath}`);

    await dailyStatsRef.transaction((currentData) => {
      let data = currentData;
      if (!data) {
        data = {
          totalCollections: 0,
          totalExpenses: 0,
          totalProfit: 0,
          collectors: {}
        };
      }

      data.totalCollections = asNumber(data.totalCollections) + collectionsDelta;
      data.totalExpenses = asNumber(data.totalExpenses) + expensesDelta;
      data.totalProfit = asNumber(data.totalProfit) + profitDelta;

      if (!data.collectors) {
          data.collectors = {};
      }

      // If it's a collector performing the action, track their specific contribution
      // In VF_SYSTEM, collectors perform COLLECT_CASH. Let's assume createdByUid is the collector.
      const actorId = createdByUid || 'system';
      if (!data.collectors[actorId]) {
         data.collectors[actorId] = {
             collections: 0,
             expenses: 0,
             profit: 0
         };
      }

      data.collectors[actorId].collections = asNumber(data.collectors[actorId].collections) + collectionsDelta;
      data.collectors[actorId].expenses = asNumber(data.collectors[actorId].expenses) + expensesDelta;
      data.collectors[actorId].profit = asNumber(data.collectors[actorId].profit) + profitDelta;

      return data;
    });
  }
);
