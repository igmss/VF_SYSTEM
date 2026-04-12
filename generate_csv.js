const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'buy_sell_transactions.json');
const csvFilePath = path.join(__dirname, 'buy_sell_transactions.csv');

try {
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const txs = data.transactions;

    const headers = ['date', 'type', 'amountEGP', 'price', 'quantityUSDT', 'from', 'to', 'orderId', 'id'];
    const csvRows = [headers.join(',')];

    for (const tx of txs) {
        const row = headers.map(header => {
            let val = tx[header] || '';
            if (typeof val === 'string' && (val.includes(',') || val.includes('"') || val.includes('\n'))) {
                val = `"${val.replace(/"/g, '""')}"`;
            }
            return val;
        });
        csvRows.push(row.join(','));
    }

    fs.writeFileSync(csvFilePath, csvRows.join('\n'));
    console.log(`CSV generated: buy_sell_transactions.csv`);

} catch (err) {
    console.error('Error generating CSV:', err);
}
