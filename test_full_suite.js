require('dotenv').config();
const URL = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const H = { 'Content-Type': 'application/json', 'Authorization': `Bearer ${KEY}` };

const BANK = '89466cca-12da-4eac-a18c-c18a9f241c13';
const COL = 'DthvqpwtP9NlSHCPgl6dhwJbnDn2';
const RET = '02de6d5d-284e-4e54-9eeb-52a3b4c55cd6';
const VF = '03740351-4538-4747-a0e2-45494f02440c';
const PAR = '5cf95fe5-e2a7-4c3c-8ed0-d954fc4ae6fa';

let pass = 0, fail = 0;

async function fn(name, body = {}, exp = 200) {
    const r = await fetch(URL + '/functions/v1/' + name, { method: 'POST', headers: H, body: JSON.stringify(body) });
    const text = await r.text();
    let j = {};
    try { j = JSON.parse(text); } catch (e) { }
    const ok = r.status === exp;
    console.log((ok ? 'OK  ' : 'FAIL') + ' ' + name + ' HTTP' + r.status + (ok ? '' : ' exp' + exp));
    if (!ok) console.log('    ', text.slice(0, 200));
    ok ? pass++ : fail++;
    return { ok, j, status: r.status };
}

async function row(table, q = '') {
    const r = await fetch(URL + '/rest/v1/' + table + '?' + q + '&limit=1', { headers: { apikey: KEY, 'Authorization': 'Bearer ' + KEY } });
    const d = await r.json();
    return Array.isArray(d) ? d[0] : d;
}

async function rows(table, q = '') {
    const r = await fetch(URL + '/rest/v1/' + table + '?' + q, { headers: { apikey: KEY, 'Authorization': 'Bearer ' + KEY } });
    return r.json();
}

function chk(label, cond, got, exp) {
    console.log('  ' + (cond ? '  ok' : '  NG') + ' ' + label + (cond ? '' : ' got=' + got + ' exp=' + exp));
}

async function main() {
    console.log('=== GROUP 1 Infrastructure ===');
    let r = await fn('ping-test');
    chk('pong+service_role', r.j.message === 'pong' && r.j.tokenRole === 'service_role', r.j.message, 'pong');
    await fn('get-business-health');
    await fn('get-performance-summary', { startDateTs: Date.now() - 604800000, endDateTs: Date.now() });
    await fn('get-investor-performance');
    await fn('get-partner-performance');

    console.log('=== GROUP 2 Bybit ===');
    await fn('bybit-test');
    r = await fn('reset-daily-limits');
    chk('reset success', r.j.success, r.j.success, true);
    await fn('manual-sync-bybit', { beginTime: Date.now() - 172800000 });
    await fn('sync-bybit-orders', { beginTime: Date.now() - 3600000 });

    console.log('=== GROUP 3 Collector/Distribution ===');
    let c0 = await row('collectors', 'id=eq.' + COL);
    let ret0 = await row('retailers', 'id=eq.' + RET);
    r = await fn('collect-retailer-cash', { collectorId: COL, retailerId: RET, amount: 100, vfAmount: 100, instaPayAmount: 0 });
    if (r.ok) {
        let c1 = await row('collectors', 'id=eq.' + COL);
        chk('cash+=100', Math.abs(c1.cash_on_hand - c0.cash_on_hand - 100) < 0.01, c1.cash_on_hand - c0.cash_on_hand, 100);
    }
    await fn('collect-retailer-cash', { collectorId: COL, retailerId: RET, amount: 99999999, vfAmount: 99999999, instaPayAmount: 0 }, 412);

    let b0 = await row('bank_accounts', 'id=eq.' + BANK);
    c0 = await row('collectors', 'id=eq.' + COL);
    r = await fn('deposit-collector-cash', { collectorId: COL, bankAccountId: BANK, amount: 100 });
    if (r.ok) {
        let b1 = await row('bank_accounts', 'id=eq.' + BANK), c1 = await row('collectors', 'id=eq.' + COL);
        chk('bank+=100', Math.abs(b1.balance - b0.balance - 100) < 0.01, b1.balance - b0.balance, 100);
        chk('cash-=100', Math.abs(c0.cash_on_hand - c1.cash_on_hand - 100) < 0.01, c0.cash_on_hand - c1.cash_on_hand, 100);
        let led = await rows('financial_ledger', 'type=eq.DEPOSIT_TO_BANK&order=timestamp.desc&limit=1');
        chk('ledger DEPOSIT_TO_BANK', led && led.length > 0, led?.length, '>0');
    }
    await fn('deposit-collector-cash', { collectorId: COL, bankAccountId: BANK, amount: 99999999 }, 412);

    let vf0 = await row('mobile_numbers', 'id=eq.' + VF);
    ret0 = await row('retailers', 'id=eq.' + RET);
    r = await fn('distribute-vf-cash', { retailerId: RET, fromVfNumberId: VF, fromVfPhone: '01020740962', amount: 200, fees: 0, chargeFeesToRetailer: false, applyCredit: false });
    if (r.ok) {
        let vf1 = await row('mobile_numbers', 'id=eq.' + VF);
        chk('vf.out+=200', Math.abs(vf1.out_total_used - vf0.out_total_used - 200) < 0.01, vf1.out_total_used - vf0.out_total_used, 200);
    }
    await fn('distribute-vf-cash', { retailerId: RET, fromVfNumberId: VF, fromVfPhone: '01020740962', amount: 99999999, fees: 0, chargeFeesToRetailer: false, applyCredit: false }, 412);

    b0 = await row('bank_accounts', 'id=eq.' + BANK);
    r = await fn('distribute-instapay', { retailerId: RET, bankAccountId: BANK, amount: 100, fees: 0, applyCredit: false });
    if (r.ok) {
        let b1 = await row('bank_accounts', 'id=eq.' + BANK);
        chk('bank-=100', Math.abs(b0.balance - b1.balance - 100) < 0.01, b0.balance - b1.balance, 100);
    }

    console.log('=== GROUP 4 Bank ===');
    b0 = await row('bank_accounts', 'id=eq.' + BANK);
    r = await fn('fund-bank-account', { bankAccountId: BANK, amount: 1000 });
    if (r.ok) {
        let b1 = await row('bank_accounts', 'id=eq.' + BANK);
        chk('fund+=1000', Math.abs(b1.balance - b0.balance - 1000) < 0.01, b1.balance - b0.balance, 1000);
        b0 = b1;
    }
    r = await fn('deduct-bank-balance', { bankAccountId: BANK, amount: 500 });
    if (r.ok) {
        let b1 = await row('bank_accounts', 'id=eq.' + BANK);
        chk('deduct-=500', Math.abs(b0.balance - b1.balance - 500) < 0.01, b0.balance - b1.balance, 500);
        b0 = b1;
    }
    let tgt = Math.round(b0.balance + 100);
    r = await fn('correct-bank-balance', { bankAccountId: BANK, newBalance: tgt });
    if (r.ok) {
        let b1 = await row('bank_accounts', 'id=eq.' + BANK);
        chk('correct to ' + tgt, Math.abs(b1.balance - tgt) < 0.01, b1.balance, tgt);
        b0 = b1;
    }
    r = await fn('correct-bank-balance', { bankAccountId: BANK, newBalance: b0.balance });
    chk('no-change returns unchanged', r.j.unchanged === true, r.j.unchanged, true);
    await fn('deduct-bank-balance', { bankAccountId: BANK, amount: 99999999 }, 412);

    console.log('=== GROUP 5 Loans ===');
    b0 = await row('bank_accounts', 'id=eq.' + BANK);
    r = await fn('issue-loan', { sourceType: 'bank', sourceId: BANK, borrowerName: 'E2E Borrower', borrowerPhone: '0100000001', amount: 300, notes: 'e2e' });
    chk('loan created', r.ok && !!r.j.loan_id, r.ok, true);
    const loanId = r.j.loan_id;
    if (loanId) {
        let b1 = await row('bank_accounts', 'id=eq.' + BANK);
        chk('bank-=300', Math.abs(b0.balance - b1.balance - 300) < 0.01, b0.balance - b1.balance, 300);
        r = await fn('record-loan-repayment', { loanId, amount: 150 });
        if (r.ok) {
            let ln = await row('loans', 'id=eq.' + loanId);
            chk('partial active', ln.status === 'active', ln.status, 'active');
        }
        r = await fn('record-loan-repayment', { loanId, amount: 150 });
        if (r.ok) {
            let ln = await row('loans', 'id=eq.' + loanId);
            chk('fully repaid', ln.status === 'fully_repaid', ln.status, 'fully_repaid');
        }
    }
    c0 = await row('collectors', 'id=eq.' + COL);
    r = await fn('issue-loan', { sourceType: 'collector', sourceId: COL, borrowerName: 'Col Loan', amount: 200 });
    if (r.ok) {
        let c1 = await row('collectors', 'id=eq.' + COL);
        chk('col cash-=200', Math.abs(c0.cash_on_hand - c1.cash_on_hand - 200) < 0.01, c0.cash_on_hand - c1.cash_on_hand, 200);
    }

    console.log('=== GROUP 6 Investors/Partners ===');
    b0 = await row('bank_accounts', 'id=eq.' + BANK);
    r = await fn('record-investor-capital', { name: 'E2E Investor', phone: '0100000002', investedAmount: 5000, initialBusinessCapital: 300000, profitSharePercent: 40, investmentDate: Date.now(), periodDays: 30, bankAccountId: BANK, notes: 'e2e' });
    chk('investor created', r.ok && !!r.j.investor_id, r.ok, true);
    const invId = r.j.investor_id;
    if (invId) {
        let b1 = await row('bank_accounts', 'id=eq.' + BANK);
        chk('bank+=5000', Math.abs(b1.balance - b0.balance - 5000) < 0.01, b1.balance - b0.balance, 5000);
        b0 = b1;
        r = await fn('get-investor-performance', { investorId: invId });
        chk('perf has investorId', r.j.investor_id === invId, r.j.investor_id, invId);
        r = await fn('pay-investor-profit', { investorId: invId, amount: 50, bankAccountId: BANK });
        if (r.ok) {
            let inv = await row('investors', 'id=eq.' + invId);
            chk('profit_paid=50', Math.abs(inv.total_profit_paid - 50) < 0.01, inv.total_profit_paid, 50);
        }
        r = await fn('withdraw-investor-capital', { investorId: invId, amount: 5000, bankAccountId: BANK });
        if (r.ok) {
            let inv = await row('investors', 'id=eq.' + invId);
            chk('status=withdrawn', inv.status === 'withdrawn', inv.status, 'withdrawn');
        }
    }
    b0 = await row('bank_accounts', 'id=eq.' + BANK);
    r = await fn('pay-partner-profit', { partnerId: PAR, amount: 50, paymentSourceType: 'bank', paymentSourceId: BANK });
    if (r.ok) {
        let b1 = await row('bank_accounts', 'id=eq.' + BANK);
        chk('bank-=50 partner', Math.abs(b0.balance - b1.balance - 50) < 0.01, b0.balance - b1.balance, 50);
    }
    vf0 = await row('mobile_numbers', 'id=eq.' + VF);
    r = await fn('pay-partner-profit', { partnerId: PAR, amount: 50, paymentSourceType: 'vf', paymentSourceId: VF });
    if (r.ok) {
        let vf1 = await row('mobile_numbers', 'id=eq.' + VF);
        chk('vf.out+=50', Math.abs(vf1.out_total_used - vf0.out_total_used - 50) < 0.01, vf1.out_total_used - vf0.out_total_used, 50);
    }

    console.log('=== GROUP 7 Snapshots/Corrections ===');
    r = await fn('rebuild-profit-snapshots', { startDate: '2026-04-01', endDate: '2026-04-24' });
    chk('snapshots built', r.j.success && r.j.snapshotsCount > 0, r.j.snapshotsCount, '>0');
    let sysSnaps = await rows('system_profit_snapshots', 'limit=1');
    chk('system_profit_snapshots rows', sysSnaps && sysSnaps.length > 0, sysSnaps?.length, '>0');
    let led = await rows('financial_ledger', 'order=timestamp.desc&limit=1');
    if (led && led.length > 0) {
        const e = led[0];
        r = await fn('correct-ledger-entry', { ledgerId: e.id, newAmount: e.amount + 1, newNotes: 'E2E correction' });
        if (r.ok) {
            let e2 = await row('financial_ledger', 'id=eq.' + e.id);
            chk('amount updated', Math.abs(e2.amount - (e.amount + 1)) < 0.01, e2.amount, e.amount + 1);
        }
    }

    console.log('=== GROUP 8 Users ===');
    const email = 'e2e_' + Date.now() + '@test.com';
    r = await fn('create-user-account', { email, password: 'TestPass123!', name: 'E2E Collector', role: 'COLLECTOR' });
    chk('user+collector created', r.ok && !!r.j.uid, r.ok, true);
    r = await fn('create-user-account', { email, password: 'TestPass123!', name: 'Dup', role: 'COLLECTOR' }, 409);
    chk('dup returns 409', r.ok, r.status, 409);
    const email2 = 'e2e_ret_' + Date.now() + '@test.com';
    r = await fn('create-user-account', { email: email2, password: 'TestPass123!', name: 'E2E Test Retailer', role: 'RETAILER', retailerId: RET });
    chk('retailer user created', r.ok && !!r.j.uid, r.ok, true);

    console.log('\n=== RESULTS: ' + pass + '/' + (pass + fail) + ' passed, ' + fail + ' failed ===');
    if (fail > 0) process.exit(1);
}
main().catch(e => { console.error(e); process.exit(1); });
