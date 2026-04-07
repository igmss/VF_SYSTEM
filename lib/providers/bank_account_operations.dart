part of 'distribution_provider.dart';

mixin BankAccountOperationsMixin on ChangeNotifier {
  /// Mixin methods access private state fields of DistributionProvider
  /// due to being part of the same library.

  Future<void> addBankAccount(BankAccount account, {String createdByUid = 'system'}) async {
    final dist = this as DistributionProvider;
    // If no banks exist, make the first one the default automatically
    if (dist._bankAccounts.isEmpty) {
      final accMap = account.toMap();
      accMap['isDefaultForBuy'] = true;
      account = BankAccount.fromMap(accMap);
    }

    await dist._db.ref('bank_accounts/${account.id}').set(account.toMap());

    // If there's an opening balance, record it as a FUND_BANK ledger entry
    if (account.balance > 0) {
      final openingTx = FinancialTransaction(
        type: FlowType.FUND_BANK,
        amount: account.balance,
        toId: account.id,
        toLabel: account.bankName,
        createdByUid: createdByUid,
        notes: 'Opening Balance',
      );
      await dist._db.ref('financial_ledger/${openingTx.id}').set(openingTx.toMap());
    }

    await dist._loadBankAccounts();
    notifyListeners();
  }

  Future<void> deleteBankAccount(String id) async {
    final dist = this as DistributionProvider;
    // BEFORE removing the bank record, mark all related ledger entries so the
    // UI can show "[Deleted Account]" instead of a dangling label.
    try {
      final ledgerSnap = await dist._db.ref('financial_ledger').get();
      if (ledgerSnap.exists && ledgerSnap.value is Map) {
        final map = Map<String, dynamic>.from(ledgerSnap.value as Map);
        final updates = <String, dynamic>{};
        for (final entry in map.entries) {
          final key = entry.key;
          final val = entry.value;
          if (val is! Map) continue;
          final row = Map<String, dynamic>.from(val);
          if (row['fromId'] == id) {
            final current = row['fromLabel']?.toString() ?? '';
            if (!current.contains('[Deleted Account]')) {
              updates['financial_ledger/$key/fromLabel'] = '$current [Deleted Account]';
            }
          }
          if (row['toId'] == id) {
            final current = row['toLabel']?.toString() ?? '';
            if (!current.contains('[Deleted Account]')) {
              updates['financial_ledger/$key/toLabel'] = '$current [Deleted Account]';
            }
          }
        }
        if (updates.isNotEmpty) {
          await dist._db.ref().update(updates);
          debugPrint('Marked ${updates.length} ledger fields as [Deleted Account] for bank $id');
        }
      }
    } catch (e) {
      debugPrint('Error stamping deleted bank ledger entries: $e');
    }
    
    // Remove the bank
    await dist._db.ref('bank_accounts/$id').remove();
    dist._bankAccounts.removeWhere((b) => b.id == id);
    // If we deleted the default bank, make the first remaining one the default
    if (dist._bankAccounts.isNotEmpty && !dist._bankAccounts.any((b) => b.isDefaultForBuy)) {
      await setDefaultBuyBank(dist._bankAccounts.first.id);
    }
    await dist._loadLedger(); // reload so in-memory ledger reflects the new labels
    notifyListeners();
  }

  /// Set Bank Account as Default for Buying USDT
  Future<void> setDefaultBuyBank(String bankId) async {
    final dist = this as DistributionProvider;
    final updates = <String, dynamic>{};
    for (final bank in dist._bankAccounts) {
      if (bank.isDefaultForBuy && bank.id != bankId) {
        updates['bank_accounts/${bank.id}/isDefaultForBuy'] = false;
      } else if (!bank.isDefaultForBuy && bank.id == bankId) {
        updates['bank_accounts/${bank.id}/isDefaultForBuy'] = true;
      }
    }
    if (updates.isNotEmpty) {
      await dist._db.ref().update(updates);
      await dist._loadBankAccounts();
      notifyListeners();
    }
  }

  /// Process a BUY_USDT action from Bybit Sync against the default bank.
  /// Deducts bank balance and records a ledger entry. Returns true if successful.
  Future<bool> processBuyOrder({
    required String bybitOrderId,
    required double usdtQuantity,
    required double egpAmount,
    required double usdtPrice,
    required DateTime timestamp,
  }) async {
    final dist = this as DistributionProvider;
    final bank = dist.defaultBuyBank;
    if (bank == null) {
      debugPrint('Buy USDT: No default bank account — recording USD Exchange increase only.');
    }

    // Safety check: is Duplicate?
    try {
      final ledgerQuery = await dist._db.ref('financial_ledger')
          .orderByChild('bybitOrderId')
          .equalTo(bybitOrderId)
          .once();
      if (ledgerQuery.snapshot.exists) {
        final items = Map<String, dynamic>.from(ledgerQuery.snapshot.value as Map);
        for (final item in items.values) {
          if (item['type'] == 'BUY_USDT') {
            debugPrint('Buy USDT: Duplicate $bybitOrderId — skipping.');
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('Buy USDT: Dedup check error (non-fatal, index may be missing): $e');
    }

    try {
      // 1. Deduct bank balance if a default bank is set
      if (bank != null) {
        await dist._db.ref('bank_accounts/${bank.id}/balance').runTransaction((Object? currentBalance) {
          if (currentBalance == null) {
            return Transaction.success(0.0 - egpAmount);
          }
          final balance = double.tryParse(currentBalance.toString()) ?? 0.0;
          return Transaction.success(balance - egpAmount);
        });
        await dist._db.ref('bank_accounts/${bank.id}/lastUpdatedAt').set(DateTime.now().toIso8601String());
      }

      // 2. Add to USD Exchange balance (USDT quantity + last price)
      await dist._addUsdtBalance(usdtQuantity, usdtPrice);

      // 3. Add ledger entry
      final tx = FinancialTransaction(
        type: FlowType.BUY_USDT,
        amount: egpAmount,
        usdtQuantity: usdtQuantity,
        usdtPrice: usdtPrice,
        fromId: bank?.id,
        fromLabel: bank?.bankName ?? 'Bank',
        toLabel: 'USD Exchange',
        bybitOrderId: bybitOrderId,
        createdByUid: 'system_sync',
        timestamp: timestamp,
      );
      await dist._db.ref('financial_ledger/${tx.id}').set(tx.toMap());

      return true;
    } catch (e) {
      debugPrint('Process Buy Order error: $e');
      return false;
    }
  }

  /// Fund a bank account (opening capital / external deposit).
  Future<void> fundBankAccount({
    required String bankAccountId,
    required double amount,
    required String createdByUid,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    final callable = dist._functions.httpsCallable('fundBankAccount');
    await callable.call({
      'bankAccountId': bankAccountId,
      'amount': amount,
      'createdByUid': createdByUid,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    await dist.loadAll();
  }

  /// Deduct from a bank account balance (for corrections / missed deductions).
  /// Records a BANK_DEDUCTION ledger entry and decreases the bank balance.
  Future<void> deductBankBalance({
    required String bankAccountId,
    required double amount,
    required String createdByUid,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    final callable = dist._functions.httpsCallable('deductBankBalance');
    await callable.call({
      'bankAccountId': bankAccountId,
      'amount': amount,
      'createdByUid': createdByUid,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    await dist.loadAll();
  }

  /// ONE-TIME: Manually correct a bank account balance by writing a correction
  /// ledger entry and updating the stored balance.
  Future<void> correctBankBalance({
    required String bankAccountId,
    required double newBalance,
    required String createdByUid,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    final callable = dist._functions.httpsCallable('correctBankBalance');
    await callable.call({
      'bankAccountId': bankAccountId,
      'newBalance': newBalance,
      'createdByUid': createdByUid,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    await dist.loadAll();
  }

  /// Finds any FUND_BANK ledger entry whose notes start with "BALANCE_CORRECTION"
  /// and converts it to a proper BANK_DEDUCTION, correcting the bank balance.
  Future<Map<String, dynamic>> fixWrongCorrectionEntry({required String createdByUid}) async {
    final dist = this as DistributionProvider;
    final wrongEntries = dist._ledger.where((tx) =>
        tx.type == FlowType.FUND_BANK &&
        (tx.notes?.startsWith('BALANCE_CORRECTION') ?? false)).toList();

    if (wrongEntries.isEmpty) {
      return {'fixed': 0, 'message': 'No wrong BALANCE_CORRECTION entries found.'};
    }

    int fixed = 0;
    for (final wrongTx in wrongEntries) {
      final bankId = wrongTx.toId; // FUND_BANK goes TO a bank
      if (bankId == null) continue;

      final bIndex = dist._bankAccounts.indexWhere((b) => b.id == bankId);
      if (bIndex == -1) continue;

      final bank = dist._bankAccounts[bIndex];
      // The wrong entry added +amount. Correct balance = current - 2*amount
      final correctedBalance = bank.balance - (wrongTx.amount * 2);

      // New proper BANK_DEDUCTION entry
      final fixTx = FinancialTransaction(
        type: FlowType.BANK_DEDUCTION,
        amount: wrongTx.amount,
        fromId: bankId,
        fromLabel: bank.bankName,
        createdByUid: createdByUid,
        notes: 'BALANCE_CORRECTION (Fixed): BUY_USDT deduction that was incorrectly recorded as credit. Ref: ${wrongTx.id}',
      );

      await Future.wait([
        dist._db.ref('financial_ledger/${wrongTx.id}').remove(),
        dist._db.ref('financial_ledger/${fixTx.id}').set(fixTx.toMap()),
        dist._db.ref('bank_accounts/$bankId/balance').set(correctedBalance),
        dist._db.ref('bank_accounts/$bankId/lastUpdatedAt').set(DateTime.now().toIso8601String()),
      ]);
      fixed++;
    }

    return {'fixed': fixed, 'message': 'Fixed $fixed wrong BALANCE_CORRECTION entries.'};
  }
}
