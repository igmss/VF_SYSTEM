require('dotenv').config();

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

async function testFunction(name, body = {}) {
    console.log(`\n--- Testing Function: ${name} ---`);
    try {
        const response = await fetch(`${SUPABASE_URL}/functions/v1/${name}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${SERVICE_ROLE_KEY}`
            },
            body: JSON.stringify(body)
        });

        const status = response.status;
        const text = await response.text();
        
        console.log(`Status: ${status}`);
        try {
            const json = JSON.parse(text);
            console.log('Response:', JSON.stringify(json, null, 2).substring(0, 500) + (text.length > 500 ? '...' : ''));
        } catch (e) {
            console.log('Raw Response:', text);
        }
        
        return status === 200;
    } catch (error) {
        console.error(`Error testing ${name}:`, error.message);
        return false;
    }
}

async function runTests() {
    console.log('Starting Edge Function Tests...');
    
    // 1. Business Health
    await testFunction('get-business-health');
    
    // 2. Performance Summary (Last 7 days)
    const now = Date.now();
    const sevenDaysAgo = now - (7 * 24 * 60 * 60 * 1000);
    await testFunction('get-performance-summary', { startDateTs: sevenDaysAgo, endDateTs: now });
    
    // 3. Investor Performance
    await testFunction('get-investor-performance');
    
    // 4. Partner Performance
    await testFunction('get-partner-performance');
    
    // 5. Rebuild Snapshots
    await testFunction('rebuild-profit-snapshots', { startDate: '2026-04-01', endDate: '2026-04-24' });
    
    // 6. Test Bybit Sync Status (Just to check connectivity)
    await testFunction('manual-sync-bybit', { limit: 1 });

    console.log('\nTests completed.');
}

runTests();
