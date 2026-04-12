const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'vodatracking-default-rtdb-export (34).json');
const outputFilePath = path.join(__dirname, 'instapay_analysis.json');

try {
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const ledger = Object.values(data.financial_ledger || {});
    
    // Filter for March 18, 2026 inclusive
    const startDate = new Date('2026-03-18T00:00:00').getTime();
    
    const instapayTxs = ledger.filter(tx => 
        (tx.type === 'DISTRIBUTE_INSTAPAY' || tx.type === 'INSTAPAY_DIST_PROFIT') &&
        tx.timestamp >= startDate
    );

    const dailyFlow = {};
    let totalProfit = 0;
    let totalPrincipalForProfit = 0;
    let totalFlowAmount = 0;

    instapayTxs.forEach(tx => {
        const date = new Date(tx.timestamp).toISOString().split('T')[0];
        
        if (tx.type === 'DISTRIBUTE_INSTAPAY') {
            dailyFlow[date] = (dailyFlow[date] || 0) + tx.amount;
            totalFlowAmount += tx.amount;
        } else if (tx.type === 'INSTAPAY_DIST_PROFIT') {
            totalProfit += tx.amount;
            
            // Extract principal from notes: "InstaPay Profit for distribution of 15600 EGP..."
            const match = tx.notes ? tx.notes.match(/distribution of ([\d.]+) EGP/) : null;
            if (match) {
                totalPrincipalForProfit += parseFloat(match[1]);
            }
        }
    });

    const sortedDailyFlow = Object.entries(dailyFlow).sort((a, b) => a[0].localeCompare(b[0]));
    
    const avgProfitPer1000 = totalPrincipalForProfit > 0 ? (totalProfit / totalPrincipalForProfit) * 1000 : 0;
    
    const result = {
        summary: {
            totalFlow: totalFlowAmount,
            totalProfit: totalProfit,
            avgProfitPer1000: avgProfitPer1000,
            count: instapayTxs.length
        },
        dailyFlow: sortedDailyFlow
    };

    fs.writeFileSync(outputFilePath, JSON.stringify(result, null, 2));
    
    console.log(`InstaPay analysis complete.`);
    console.log(`Total InstaPay Flow: ${totalFlowAmount.toLocaleString()} EGP`);
    console.log(`Average Profit per 1000: ${avgProfitPer1000.toFixed(2)} EGP`);
    console.log(`Daily Flow Breakdown:`, sortedDailyFlow);

} catch (err) {
    console.error('Error processing InstaPay data:', err);
}
