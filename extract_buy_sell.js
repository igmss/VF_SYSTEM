const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'vodatracking-default-rtdb-export (34).json');
const outputFilePath = path.join(__dirname, 'buy_sell_transactions.json');

try {
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const ledger = data.financial_ledger || {};
    
    // Filter for March 18, 2026 00:00:00 GMT+2
    const startDate = new Date('2026-03-18T00:00:00').getTime();
    
    const buySellTransactions = Object.values(ledger).filter(tx => 
        (tx.type === 'BUY_USDT' || tx.type === 'SELL_USDT') &&
        tx.timestamp >= startDate
    );

    // Sort by timestamp
    buySellTransactions.sort((a, b) => a.timestamp - b.timestamp);

    const result = {
        count: buySellTransactions.length,
        summary: {
            buy: buySellTransactions.filter(tx => tx.type === 'BUY_USDT').length,
            sell: buySellTransactions.filter(tx => tx.type === 'SELL_USDT').length,
            totalAmountBuy: buySellTransactions.filter(tx => tx.type === 'BUY_USDT').reduce((acc, tx) => acc + (tx.amount || 0), 0),
            totalAmountSell: buySellTransactions.filter(tx => tx.type === 'SELL_USDT').reduce((acc, tx) => acc + (tx.amount || 0), 0),
            totalQuantityBuy: buySellTransactions.filter(tx => tx.type === 'BUY_USDT').reduce((acc, tx) => acc + (tx.usdtQuantity || 0), 0),
            totalQuantitySell: buySellTransactions.filter(tx => tx.type === 'SELL_USDT').reduce((acc, tx) => acc + (tx.usdtQuantity || 0), 0),
        },
        transactions: buySellTransactions.map(tx => ({
            id: tx.id,
            date: new Date(tx.timestamp).toLocaleString(),
            timestamp: tx.timestamp,
            type: tx.type,
            amountEGP: tx.amount,
            price: tx.usdtPrice,
            quantityUSDT: tx.usdtQuantity,
            from: tx.fromLabel,
            to: tx.toLabel,
            orderId: tx.bybitOrderId
        }))
    };

    fs.writeFileSync(outputFilePath, JSON.stringify(result, null, 2));
    
    console.log(`Extraction complete.`);
    console.log(`Total Buy/Sell Transactions: ${result.count}`);
    console.log(`Buy: ${result.summary.buy}`);
    console.log(`Sell: ${result.summary.sell}`);
    console.log(`Results saved to buy_sell_transactions.json`);

} catch (err) {
    console.error('Error processing file:', err);
}
