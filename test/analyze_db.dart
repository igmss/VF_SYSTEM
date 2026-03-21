import 'dart:convert';
import 'dart:io';

void main() async {
  final file = File('d:\\New folder\\vodafone_system\\vodatracking-default-rtdb-export.json');
  if (!file.existsSync()) {
    print('File not found');
    return;
  }
  
  final String content = await file.readAsString();
  final data = jsonDecode(content) as Map<String, dynamic>;
  
  final ledgerData = data['financial_ledger'] as Map<String, dynamic>? ?? {};
  final usdExchangeData = data['usd_exchange'] as Map<String, dynamic>? ?? {};
  final bankData = data['bank_accounts'] as Map<String, dynamic>? ?? {};
  final transactionsData = data['transactions'] as Map<String, dynamic>? ?? {};
  
  final march18 = DateTime(2026, 3, 18);
  
  double usdtBought = 0;
  double usdtSold = 0;
  double bankInwards = 0;
  double bankOutwards = 0;
  int missingOrderCount = 0;
  
  print('=== FIREBASE DB ANALYSIS SINCE 18/3 ===\\n');
  print('CURRENT STATE IN FIREBASE:');
  print('  USD Exchange Balance: ${usdExchangeData['usdtBalance']} USDT');
  
  print('\\nCurrent Bank balances:');
  final Map<String, Map<String, dynamic>> banks = {};
  bankData.forEach((key, value) {
    if (value is Map) {
      banks[key] = Map<String, dynamic>.from(value);
      print('  ${value['bankName']}: ${value['balance']} EGP');
    }
  });
  
  print('\\n--- LEDGER SINCE 18/3 ---');
  final ledgerItems = ledgerData.values.whereType<Map<String, dynamic>>().toList();
  ledgerItems.sort((a, b) {
    int ta = a['timestamp'] ?? 0;
    int tb = b['timestamp'] ?? 0;
    return ta.compareTo(tb);
  });
  
  for (final item in ledgerItems) {
    int ts = item['timestamp'] ?? 0;
    DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts);
    if (dt.isBefore(march18)) continue;
    
    String type = item['type'] ?? '';
    double amount = (item['amount'] ?? 0).toDouble();
    double usdtQty = (item['usdtQuantity'] ?? 0).toDouble();
    
    // Skip ADMIN_ADJUSTMENT because it modifies another TX, but wait, the ledger exported JSON has the modified amounts.
    if (type == 'ADMIN_ADJUSTMENT') continue;
    
    if (type == 'BUY_USDT') {
      usdtBought += usdtQty;
      bankOutwards += amount;
    } else if (type == 'SELL_USDT') {
      usdtSold += usdtQty;
    } else if (type == 'FUND_BANK' || type == 'DEPOSIT_TO_BANK') {
      bankInwards += amount;
    } else if (type == 'BANK_DEDUCTION') {
      bankOutwards += amount;
    }
  }
  
  print('\\n--- CALCULATED FLOW SINCE 18/3 ---');
  print('  Total USDT Bought: +$usdtBought USDT');
  print('  Total USDT Sold:  -$usdtSold USDT');
  print('  NET USDT Change:  ${(usdtBought - usdtSold).toStringAsFixed(2)} USDT');
  print('');
  print('  Total Bank Inwards:  +$bankInwards EGP');
  print('  Total Bank Outwards: -$bankOutwards EGP');
  print('  NET Bank Change:     ${(bankInwards - bankOutwards).toStringAsFixed(2)} EGP');
  
  print('\\n--- CHECKING FOR MISSING ORDERS SINCE 18/3 ---');
  final bybitOrderIdsInLedger = ledgerItems.map((e) => e['bybitOrderId'].toString()).toSet();
  
  final txItems = transactionsData.values.whereType<Map<String, dynamic>>().toList();
  for (final tx in txItems) {
    if (tx['status'] != 'completed') continue;
    DateTime ts = DateTime.tryParse(tx['timestamp'] ?? DateTime.now().toIso8601String()) ?? DateTime.now();
    if (ts.isBefore(march18)) continue;
    
    final oid = tx['bybitOrderId']?.toString();
    // Only flag true Bybit Order IDs (numerical)
    if (oid != null && oid.isNotEmpty && !oid.startsWith('DIST') && !bybitOrderIdsInLedger.contains(oid)) {
      print('  MISSING FROM LEDGER (Bybit Order): $oid');
      missingOrderCount++;
    }
  }
  if (missingOrderCount == 0) {
    print('  All numeric Bybit orders since 18/3 are successfully in the Ledger!');
  }
}
