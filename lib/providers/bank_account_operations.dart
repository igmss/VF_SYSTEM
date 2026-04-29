part of 'distribution_provider.dart';

mixin BankAccountOperationsMixin on ChangeNotifier {
  Future<void> addBankAccount(BankAccount account, {String createdByUid = 'system'}) async {
    final dist = this as DistributionProvider;
    try {
      await dist._supabase.from('bank_accounts').upsert({
        'id': account.id,
        'bank_name': account.bankName,
        'account_number': account.accountNumber,
        'account_holder': account.accountHolder,
        'balance': account.balance,
        'is_default_for_buy': account.isDefaultForBuy,
      });
      
      if (account.balance > 0) {
        await dist._supabase.from('financial_ledger').insert({
          'type': 'FUND_BANK',
          'amount': account.balance,
          'to_id': account.id,
          'to_label': account.bankName,
          'created_by_uid': createdByUid,
          'notes': 'Opening Balance',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (e) {
      debugPrint('Error adding bank account to Supabase: $e');
    }
  }

  Future<void> deleteBankAccount(String id) async {
    final dist = this as DistributionProvider;
    try {
      await dist._supabase.from('bank_accounts').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting bank account from Supabase: $e');
    }
    notifyListeners();
  }

  Future<void> setDefaultBuyBank(String bankId) async {
    final dist = this as DistributionProvider;
    try {
      await dist._supabase.rpc('set_default_bank', params: {'p_bank_id': bankId});
    } catch (e) {
      debugPrint('Error setting default bank in Supabase: $e');
    }
  }

  Future<bool> processBuyOrder({
    required String bybitOrderId,
    required double usdtQuantity,
    required double egpAmount,
    required double usdtPrice,
    required DateTime timestamp,
  }) async {
    final dist = this as DistributionProvider;
    try {
      final response = await dist._supabase.functions.invoke('sync-bybit-orders', body: {
        'orderId': bybitOrderId,
        'force': true, // Assuming we want to force this specific one if called manually
      });
      return response.status == 200;
    } catch (e) {
      debugPrint('Process Buy Order error in Supabase: $e');
      return false;
    }
  }

  Future<void> fundBankAccount({
    required String bankAccountId,
    required double amount,
    required String createdByUid,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    try {
      await dist._supabase.rpc('fund_bank_account', params: {
        'p_bank_account_id': bankAccountId,
        'p_amount': amount,
        'p_created_by_uid': createdByUid,
        'p_notes': notes,
      });
    } catch (e) {
      debugPrint('Error funding bank account in Supabase: $e');
    }
  }

  Future<void> deductBankBalance({
    required String bankAccountId,
    required double amount,
    required String createdByUid,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    try {
      await dist._supabase.rpc('deduct_bank_balance', params: {
        'p_bank_account_id': bankAccountId,
        'p_amount': amount,
        'p_created_by_uid': createdByUid,
        'p_notes': notes,
      });
    } catch (e) {
      debugPrint('Error deducting bank balance in Supabase: $e');
    }
  }

  Future<void> correctBankBalance({
    required String bankAccountId,
    required double newBalance,
    required String createdByUid,
    String? notes,
  }) async {
    final dist = this as DistributionProvider;
    try {
      await dist._supabase.rpc('correct_bank_balance', params: {
        'p_bank_account_id': bankAccountId,
        'p_new_balance': newBalance,
        'p_created_by_uid': createdByUid,
        'p_notes': notes,
      });
    } catch (e) {
      debugPrint('Error correcting bank balance in Supabase: $e');
    }
  }

  Future<Map<String, dynamic>> fixWrongCorrectionEntry({required String createdByUid}) async {
    // This was a one-time fix for Firebase data corruption.
    // In Supabase, we don't expect this, so we return a dummy success.
    return {'fixed': 0, 'message': 'Not required for Supabase.'};
  }
}
