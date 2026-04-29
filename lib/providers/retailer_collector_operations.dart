part of 'distribution_provider.dart';

mixin RetailerCollectorOperationsMixin on ChangeNotifier {
  Future<int> roundAllRetailerAssignments() async {
    final dist = this as DistributionProvider;
    // Rounding is best done via RPC in Supabase
    try {
      final response = await dist._supabase.rpc('round_all_retailer_assignments');
      return (response as int?) ?? 0;
    } catch (e) {
      debugPrint('Error rounding assignments in Supabase: $e');
      return 0;
    }
  }

  Future<void> addRetailer(Retailer retailer) async {
    final dist = this as DistributionProvider;
    await dist._supabase.from('retailers').upsert({
      'id': retailer.id,
      'name': retailer.name,
      'phone': retailer.phone,
      'assigned_collector_id': retailer.assignedCollectorId,
      'discount_per_1000': retailer.discountPer1000,
      'insta_pay_profit_per_1000': retailer.instaPayProfitPer1000,
      'area': retailer.area,
      'is_active': retailer.isActive,
    });
  }

  Future<void> updateRetailer(Retailer retailer) async {
    final dist = this as DistributionProvider;
    await dist._supabase.from('retailers').update({
      'name': retailer.name,
      'phone': retailer.phone,
      'assigned_collector_id': retailer.assignedCollectorId,
      'discount_per_1000': retailer.discountPer1000,
      'insta_pay_profit_per_1000': retailer.instaPayProfitPer1000,
      'area': retailer.area,
      'is_active': retailer.isActive,
    }).eq('id', retailer.id);
  }

  Future<void> deactivateRetailer(String id) async {
    final dist = this as DistributionProvider;
    await dist._supabase.from('retailers').update({'is_active': false}).eq('id', id);
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
    if (dist._isDistributing) throw StateError('An assignment is already in progress.');
    dist._isDistributing = true;
    notifyListeners();
    try {
      await dist._supabase.rpc('distribute_vf_cash', params: {
        'p_retailer_id': retailerId,
        'p_from_vf_number_id': fromVfNumberId,
        'p_amount': amount,
        'p_fees': fees,
        'p_charge_fees_to_retailer': chargeFeesToRetailer,
        'p_apply_credit': applyCredit,
        'p_created_by_uid': createdByUid,
        'p_notes': notes,
      });
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
    if (dist._isDistributing) throw StateError('An assignment is already in progress.');
    dist._isDistributing = true;
    notifyListeners();
    try {
      await dist._supabase.rpc('distribute_insta_pay', params: {
        'p_retailer_id': retailerId,
        'p_bank_account_id': bankAccountId,
        'p_amount': amount,
        'p_fees': fees,
        'p_apply_credit': applyCredit,
        'p_created_by_uid': createdByUid,
        'p_notes': notes,
      });
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
    if (dist._isDistributing) throw StateError('An assignment is already in progress.');
    dist._isDistributing = true;
    notifyListeners();
    try {
      await dist._supabase.functions.invoke('process-retailer-request', body: {
        'portalUserUid': portalUserUid,
        'requestId': requestId,
        'status': status,
        'proofImageUrl': proofImageUrl ?? '',
        'adminNotes': adminNotes,
        if (status == 'COMPLETED') ...{
          'retailerId': retailerId,
          'fromVfNumberId': fromVfNumberId,
          'amount': amount,
          'fees': fees,
          'chargeFeesToRetailer': chargeFeesToRetailer,
          'applyCredit': applyCredit,
        }
      });
    } finally {
      dist._isDistributing = false;
      notifyListeners();
    }
  }

  Future<void> collectFromRetailer({
    required String collectorId,
    required String retailerId,
    required double amount,
    required String createdByUid,
    double vfCollected = 0.0,
    double ipCollected = 0.0,
    double addedToCredit = 0.0,
    double vfAmount = 0.0,
    double instaPayAmount = 0.0,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    if (dist._isCollecting) throw StateError('A collection is already in progress.');
    dist._isCollecting = true;
    notifyListeners();
    try {
      await dist._supabase.rpc('collect_retailer_cash_tx', params: {
        'p_collector_id': collectorId,
        'p_retailer_id': retailerId,
        'p_amount': amount,
        'p_vf_amount': vfAmount,
        'p_insta_pay_amount': instaPayAmount,
        'p_notes': notes,
        'p_vf_collected': vfCollected,
        'p_ip_collected': ipCollected,
        'p_added_to_credit': addedToCredit,
        'p_uid': createdByUid,
        'p_timestamp': DateTime.now().millisecondsSinceEpoch,
      });
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
    if (dist._isDepositing) throw StateError('A deposit is already in progress.');
    dist._isDepositing = true;
    notifyListeners();
    try {
      await dist._supabase.rpc('deposit_collector_cash', params: {
        'p_collector_id': collectorId,
        'p_bank_account_id': bankAccountId,
        'p_amount': amount,
        'p_created_by_uid': createdByUid,
        'p_notes': notes,
      });
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
    if (dist._isDepositing) throw StateError('A deposit is already in progress.');
    dist._isDepositing = true;
    notifyListeners();
    try {
      // Find default VF number
      final vfResponse = await dist._supabase.from('mobile_numbers').select('id').eq('is_default', true).maybeSingle();
      if (vfResponse == null) throw Exception('No default VF number found.');
      
      await dist._supabase.rpc('deposit_collector_cash_to_vf', params: {
        'p_collector_id': collectorId,
        'p_vf_number_id': vfResponse['id'],
        'p_amount': amount,
        'p_created_by_uid': createdByUid,
        'p_notes': notes,
      });
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
      await dist._supabase.rpc('correct_financial_transaction', params: {
        'p_transaction_id': originalTx.id,
        'p_correct_amount': correctAmount,
        'p_reason': reason,
      });
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
    try {
      await dist._supabase.functions.invoke('sync-bybit-orders', body: {
        'orderId': bybitOrderId,
        'force': true,
      });
    } catch (e) {
      debugPrint('Error recordBybitBuyOrder in Supabase: $e');
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
      await dist._supabase.functions.invoke('sync-bybit-orders', body: {
        'orderId': bybitOrderId,
        'force': true,
      });
    } catch (e) {
      debugPrint('Error recordBybitSellOrder in Supabase: $e');
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
    if (dist._isCreditReturning) throw StateError('A credit return is already in progress.');
    dist._isCreditReturning = true;
    notifyListeners();
    try {
      await dist._supabase.rpc('credit_return', params: {
        'p_retailer_id': retailerId,
        'p_vf_number_id': vfNumberId,
        'p_amount': amount,
        'p_fees': fees,
        'p_created_by_uid': createdByUid,
        'p_notes': notes,
      });
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
    if (dist._isInternalTransferring) throw StateError('An internal transfer is already in progress.');
    dist._isInternalTransferring = true;
    notifyListeners();
    try {
      await dist._supabase.rpc('transfer_internal_vf_cash', params: {
        'p_from_vf_id': fromVfId,
        'p_to_vf_id': toVfId,
        'p_amount': amount,
        'p_fees': fees,
        'p_notes': notes,
      });
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
      await dist._supabase.rpc('delete_financial_transaction', params: {
        'p_transaction_id': tx.id,
      });
    } finally {
      dist._isDeleting = false;
    }
  }
  
  // Stubs for Collector logic
  Future<void> addCollector(Collector collector) async {
    final dist = this as DistributionProvider;
    await dist._supabase.from('collectors').upsert({
      'id': collector.id,
      'uid': collector.uid,
      'name': collector.name,
      'phone': collector.phone,
      'email': collector.email,
      'is_active': collector.isActive,
    });
  }

  Future<void> updateCollector(Collector collector) async {
    final dist = this as DistributionProvider;
    await dist._supabase.from('collectors').update({
      'name': collector.name,
      'phone': collector.phone,
      'email': collector.email,
      'is_active': collector.isActive,
    }).eq('id', collector.id);
  }

  Future<void> deactivateCollector(String id) async {
    final dist = this as DistributionProvider;
    await dist._supabase.from('collectors').update({'is_active': false}).eq('id', id);
  }
}
