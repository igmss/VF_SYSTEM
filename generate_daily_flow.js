const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'buy_sell_transactions.json');
const outputFilePath = path.join(__dirname, 'daily_sell_flow.csv');

try {
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const sells = data.transactions.filter(tx => tx.type === 'SELL_USDT');
    
    const daily = {};
    sells.forEach(tx => {
        const date = new Date(tx.timestamp).toISOString().split('T')[0];
        daily[date] = (daily[date] || 0) + tx.amountEGP;
    });

    const sorted = Object.entries(daily).sort((a, b) => a[0].localeCompare(b[0]));
    
    const headers = ['Date', 'Total Sell Flow (EGP)'];
    const csvRows = [headers.join(',')];
    
    for (const [date, amount] of sorted) {
        csvRows.push(`${date},${amount.toFixed(2)}`);
    }

    fs.writeFileSync(outputFilePath, csvRows.join('\n'));
    
    console.log(`Daily sell flow CSV generated.`);
    
    // Print table to console for the user
    console.log('\n| Date | Total Sell Flow (EGP) |');
    console.log('| :--- | :--- |');
    for (const [date, amount] of sorted) {
        console.log(`| ${date} | ${amount.toLocaleString()} EGP |`);
    }

} catch (err) {
    console.error('Error generating daily flow:', err);
}
