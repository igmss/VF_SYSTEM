part of 'distribution_provider.dart';

mixin RetailerCollectorOperationsMixin on ChangeNotifier {
  /// Mixin methods access private state fields of DistributionProvider
  /// due to being part of the same library.

  Future<int> roundAllRetailerAssignments() async {
    final dist = this as DistributionProvider;
    int fixed = 0;
    for (final retailer in dist._retailers) {
      final rounded = retailer.totalAssigned.ceilToDouble();
      if (rounded != retailer.totalAssigned) {
        await dist._db.ref('retailers/${retailer.id}/totalAssigned').set(rounded);
        fixed++;
      }
    }
    await dist._loadRetailers();
    notifyListeners();
    return fixed;
  }

  Future<void> addRetailer(Retailer retailer) async {
    final dist = this as DistributionProvider;
    await dist._db.ref('retailers/${retailer.id}').set(retailer.toMap());
    await dist._loadRetailers();
    notifyListeners();
  }

  Future<void> updateRetailer(Retailer retailer) async {
    final dist = this as DistributionProvider;
    await dist._db.ref('retailers/${retailer.id}').update(retailer.toMap());
    await dist._loadRetailers();
    notifyListeners();
  }

  Future<void> deactivateRetailer(String id) async {
    final dist = this as DistributionProvider;
    await dist._db.ref('retailers/$id/isActive').set(false);
    dist._retailers.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  Future<void> distributeVfCash({
    required String retailerId,
    required String fromVfNumberId,
    required String fromVfPhone,
    required double amount,
    double fees = 0.0,
    bool chargeFeesToRetailer = false,
    bool applyCredit = false,
    required String createdByUid,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    if (dist._isDistributing) {
      throw StateError('An assignment is already in progress.');
    }
    dist._isDistributing = true;
    notifyListeners();
    try {
      final callable = dist._functions.httpsCallable('distributeVfCash');
      await callable.call({
        'retailerId': retailerId,
        'fromVfNumberId': fromVfNumberId,
        'fromVfPhone': fromVfPhone,
        'amount': amount,
        'fees': fees,
        'chargeFeesToRetailer': chargeFeesToRetailer,
        'applyCredit': applyCredit,
        'createdByUid': createdByUid,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      });
      await dist.loadAll();
    } finally {
      dist._isDistributing = false;
      notifyListeners();
    }
  }

  Future<void> distributeInstaPay({
    required String retailerId,
    required String bankAccountId,
    required double amount,
    double fees = 0.0,
    bool applyCredit = false,
    required String createdByUid,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    if (dist._isDistributing) {
      throw StateError('An assignment is already in progress.');
    }
    dist._isDistributing = true;
    notifyListeners();
    print('--- PROV: distributeInstaPay START ---');
    print('    Retailer: $retailerId, Bank: $bankAccountId, Amt: $amount, Fees: $fees');
    try {
      final callable = dist._functions.httpsCallable('distributeInstaPay');
      final result = await callable.call({
        'retailerId': retailerId,
        'bankAccountId': bankAccountId,
        'amount': amount,
        'fees': fees,
        'applyCredit': applyCredit,
        'createdByUid': createdByUid,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      });
      print('--- PROV: distributeInstaPay SUCCESS ---');
      print('    Result: ${result.data}');
      await dist.loadAll();
    } catch (e) {
      print('--- PROV: distributeInstaPay ERROR ---');
      print('    Error: $e');
      rethrow;
    } finally {
      dist._isDistributing = false;
      notifyListeners();
    }
  }

  Future<void> processRetailerRequest({
    required String portalUserUid,
    required String requestId,
    required String status,
    String? proofImageUrl,
    String? adminNotes,
    String? retailerId,
    String? fromVfNumberId,
    String? fromVfPhone,
    double? amount,
    double fees = 0.0,
    bool chargeFeesToRetailer = false,
    bool applyCredit = false,
  }) async {
    final dist = this as DistributionProvider;
    if (dist._isDistributing) {
      throw StateError('An assignment is already in progress.');
    }
    dist._isDistributing = true;
    notifyListeners();
    try {
      final callable = dist._functions.httpsCallable('processRetailerRequest');
      await callable.call({
        'portalUserUid': portalUserUid,
        'requestId': requestId,
        'status': status,
        'proofImageUrl': proofImageUrl ?? '',
        if (adminNotes != null && adminNotes.trim().isNotEmpty) 'adminNotes': adminNotes.trim(),
        if (status == 'COMPLETED') ...{
          'retailerId': retailerId,
          'fromVfNumberId': fromVfNumberId,
          'fromVfPhone': fromVfPhone,
          'amount': amount,
          'fees': fees,
          'chargeFeesToRetailer': chargeFeesToRetailer,
          'applyCredit': applyCredit,
        }
      });
      await dist.loadAll();
    } finally {
      dist._isDistributing = false;
      notifyListeners();
    }
  }

  Future<void> addCollector(Collector collector) async {
    final dist = this as DistributionProvider;
    await dist._db.ref('collectors/${collector.id}').set(collector.toMap());
    await dist._loadCollectors();
    notifyListeners();
  }

  Future<void> updateCollector(Collector collector) async {
    final dist = this as DistributionProvider;
    await dist._db.ref('collectors/${collector.id}').update(collector.toMap());
    await dist._loadCollectors();
    notifyListeners();
  }

  Future<void> deactivateCollector(String id) async {
    final dist = this as DistributionProvider;
    await dist._db.ref('collectors/$id/isActive').set(false);
    dist._collectors.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  Future<void> collectFromRetailer({
    required String collectorId,
    required String retailerId,
    required double amount,
    required String createdByUid,
    double vfAmount = 0.0,
    double instaPayAmount = 0.0,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    if (dist._isCollecting) {
      throw StateError('A collection is already in progress.');
    }
    if (amount <= 0) {
      throw ArgumentError('Collection amount must be greater than zero.');
    }
    dist._isCollecting = true;
    notifyListeners();
    try {
      final callable = dist._functions.httpsCallable('collectRetailerCash');
      await callable.call({
        'collectorId': collectorId,
        'retailerId': retailerId,
        'amount': amount,
        'vfAmount': vfAmount,
        'instaPayAmount': instaPayAmount,
        'createdByUid': createdByUid,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      });
      await dist._refreshOperationalData();
    } finally {
      dist._isCollecting = false;
      notifyListeners();
    }
  }

  Future<void> depositToBank({
    required String collectorId,
    required String bankAccountId,
    required double amount,
    required String createdByUid,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    if (dist._isDepositing) {
      throw StateError('A deposit is already in progress.');
    }
    if (amount <= 0) {
      throw ArgumentError('Deposit amount must be greater than zero.');
    }
    dist._isDepositing = true;
    notifyListeners();
    try {
      final callable = dist._functions.httpsCallable('depositCollectorCash');
      await callable.call({
        'collectorId': collectorId,
        'bankAccountId': bankAccountId,
        'amount': amount,
        'createdByUid': createdByUid,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      });
      await dist._refreshOperationalData();
    } finally {
      dist._isDepositing = false;
      notifyListeners();
    }
  }

  Future<void> depositToDefaultVf({
    required String collectorId,
    required double amount,
    required String createdByUid,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    if (dist._isDepositing) {
      throw StateError('A deposit is already in progress.');
    }
    if (amount <= 0) {
      throw ArgumentError('Deposit amount must be greater than zero.');
    }
    dist._isDepositing = true;
    notifyListeners();
    try {
      final callable = dist._functions.httpsCallable('depositCollectorCashToDefaultVf');
      await callable.call({
        'collectorId': collectorId,
        'amount': amount,
        'createdByUid': createdByUid,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      });
      await dist._refreshOperationalData();
    } finally {
      dist._isDepositing = false;
      notifyListeners();
    }
  }

  Future<void> correctTransaction({
    required FinancialTransaction originalTx,
    required double correctAmount,
    required String adminUid,
    String? reason,
  }) async {
    final dist = this as DistributionProvider;
    if (dist._isCorrecting) return;
    dist._isCorrecting = true;
    try {
      final callable = dist._functions.httpsCallable('correctFinancialTransaction');
      await callable.call({
        'transactionId': originalTx.id,
        'correctAmount': correctAmount,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
      await dist.loadAll();
    } catch (e) {
      debugPrint('Correction error: $e');
      rethrow;
    } finally {
      dist._isCorrecting = false;
    }
  }

  Future<void> recordBybitBuyOrder({
    required String bybitOrderId,
    required double egpAmount,
    required double usdtQuantity,
    required double usdtPrice,
    required String paymentMethod,
    required String? matchedBankAccountId,
    required String matchedBankLabel,
    required String createdByUid,
  }) async {
    final dist = this as DistributionProvider;
    // 1. Strict deduplication check
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
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Buy USDT: CRITICAL Dedup check error. Halting to prevent duplicates: $e');
      return;
    }

    final tx = FinancialTransaction(
      id: 'buy_${bybitOrderId}',
      type: FlowType.BUY_USDT,
      amount: egpAmount,
      usdtPrice: usdtPrice,
      usdtQuantity: usdtQuantity,
      fromId: matchedBankAccountId,
      fromLabel: matchedBankLabel,
      toLabel: 'USD Exchange',
      bybitOrderId: bybitOrderId,
      paymentMethod: paymentMethod,
      createdByUid: createdByUid,
      timestamp: DateTime.now(),
    );

    if (matchedBankAccountId != null) {
      await dist._db.ref('bank_accounts/$matchedBankAccountId/balance').runTransaction((Object? data) {
        final current = (data as num?)?.toDouble() ?? 0.0;
        return Transaction.success(current - egpAmount);
      });
    }
    // Add to USD Exchange balance (USDT quantity)
    await dist._addUsdtBalance(usdtQuantity, usdtPrice);
    await dist._db.ref('financial_ledger/${tx.id}').set(tx.toMap());

    if (usdtPrice > 0) {
      await dist._db.ref('price_history/${tx.id}').set({
        'price': usdtPrice,
        'side': 'buy',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<void> recordBybitSellOrder({
    required String bybitOrderId,
    required double egpAmount,
    required double usdtQuantity,
    required double usdtPrice,
    required String paymentMethod,
    required String? vfNumberId,
    required String vfNumberLabel,
    required String createdByUid,
    required DateTime timestamp,
  }) async {
    final dist = this as DistributionProvider;
    try {
      final ledgerQuery = await dist._db.ref('financial_ledger')
          .orderByChild('bybitOrderId')
          .equalTo(bybitOrderId)
          .once();
      if (ledgerQuery.snapshot.exists) {
        final items = Map<String, dynamic>.from(ledgerQuery.snapshot.value as Map);
        for (final item in items.values) {
          if (item['type'] == 'SELL_USDT') {
            debugPrint('Sell USDT: Duplicate $bybitOrderId — skipping.');
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Sell USDT: CRITICAL Dedup check error. Halting to prevent duplicates: $e');
      return;
    }

    try {
      final tx = FinancialTransaction(
        id: 'sell_${bybitOrderId}',
        type: FlowType.SELL_USDT,
        amount: egpAmount,
        usdtPrice: usdtPrice,
        usdtQuantity: usdtQuantity,
        fromLabel: 'USD Exchange',
        toId: vfNumberId,
        toLabel: vfNumberLabel,
        bybitOrderId: bybitOrderId,
        paymentMethod: paymentMethod,
        createdByUid: createdByUid,
        timestamp: timestamp,
      );
      // Subtract from USD Exchange balance (USDT quantity)
      await dist._subtractUsdtBalance(usdtQuantity, usdtPrice);
      await dist._db.ref('financial_ledger/${tx.id}').set(tx.toMap());

      if (usdtPrice > 0) {
        await dist._db.ref('price_history/${tx.id}').set({
          'price': usdtPrice,
          'side': 'sell',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (e) {
      debugPrint('Process Sell Order error: $e');
    }
  }

  Future<void> creditReturn({
    required String retailerId,
    required String vfNumberId,
    required String vfPhone,
    required double amount,
    required double fees,
    required String createdByUid,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    if (dist._isCreditReturning) {
      throw StateError('A credit return is already in progress.');
    }
    dist._isCreditReturning = true;
    notifyListeners();
    try {
      final callable = dist._functions.httpsCallable('creditReturn');
      await callable.call({
        'retailerId': retailerId,
        'vfNumberId': vfNumberId,
        'vfPhone': vfPhone,
        'amount': amount,
        'fees': fees,
        'createdByUid': createdByUid,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      });
      await dist.loadAll();
    } catch (e) {
      debugPrint('Credit Return error: ');
      rethrow;
    } finally {
      dist._isCreditReturning = false;
      notifyListeners();
    }
  }

  Future<void> transferInternalVfCash({
    required String fromVfId,
    required String toVfId,
    required double amount,
    required double fees,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    if (dist._isInternalTransferring) {
      throw StateError('An internal transfer is already in progress.');
    }
    dist._isInternalTransferring = true;
    notifyListeners();
    try {
      final callable = dist._functions.httpsCallable('transferInternalVfCash');
      await callable.call({
        'fromVfId': fromVfId,
        'toVfId': toVfId,
        'amount': amount,
        'fees': fees,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      });
      await dist.loadAll();
    } catch (e) {
      debugPrint('Internal Transfer error: $e');
      rethrow;
    } finally {
      dist._isInternalTransferring = false;
      notifyListeners();
    }
  }

  Future<void> deleteTransaction(FinancialTransaction tx) async {
    final dist = this as DistributionProvider;
    if (dist._isDeleting) return;
    dist._isDeleting = true;
    try {
      final callable = dist._functions.httpsCallable('deleteFinancialTransaction');
      await callable.call({
        'transactionId': tx.id,
      });
      await dist.loadAll();
    } catch (e) {
      debugPrint('Delete transaction error: $e');
      rethrow;
    } finally {
      dist._isDeleting = false;
    }
  }
}
