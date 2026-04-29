import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

class DatabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _numbersTable = 'mobile_numbers';
  static const String _transactionsTable = 'transactions';
  static const String _syncTable = 'sync_state';

  // ── Helpers ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _mapNumberToCamel(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'phoneNumber': row['phone_number'],
      'name': row['name'],
      'isDefault': row['is_default'],
      'createdAt': row['created_at'],
      'lastUpdatedAt': row['last_updated_at'],
      'initialBalance': row['initial_balance'],
      'inDailyLimit': row['in_daily_limit'],
      'inMonthlyLimit': row['in_monthly_limit'],
      'outDailyLimit': row['out_daily_limit'],
      'outMonthlyLimit': row['out_monthly_limit'],
      'inDailyUsed': row['in_daily_used'],
      'inMonthlyUsed': row['in_monthly_used'],
      'outDailyUsed': row['out_daily_used'],
      'outMonthlyUsed': row['out_monthly_used'],
      'inTotalUsed': row['in_total_used'],
      'outTotalUsed': row['out_total_used'],
    };
  }

  Map<String, dynamic> _mapNumberToSnake(MobileNumber number) {
    return {
      'id': number.id,
      'phone_number': number.phoneNumber,
      'name': number.name,
      'is_default': number.isDefault,
      'created_at': number.createdAt.toIso8601String(),
      'last_updated_at': number.lastUpdatedAt.toIso8601String(),
      'initial_balance': number.initialBalance,
      'in_daily_limit': number.inDailyLimit,
      'in_monthly_limit': number.inMonthlyLimit,
      'out_daily_limit': number.outDailyLimit,
      'out_monthly_limit': number.outMonthlyLimit,
      'in_daily_used': number.inDailyUsed,
      'in_monthly_used': number.inMonthlyUsed,
      'out_daily_used': number.outDailyUsed,
      'out_monthly_used': number.outMonthlyUsed,
      'in_total_used': number.inTotalUsed,
      'out_total_used': number.outTotalUsed,
    };
  }

  Map<String, dynamic> _mapTxToCamel(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'phoneNumber': row['phone_number'],
      'amount': row['amount'],
      'currency': row['currency'],
      'timestamp': row['timestamp'],
      'bybitOrderId': row['bybit_order_id'],
      'status': row['status'],
      'paymentMethod': row['payment_method'],
      'side': row['side'],
      'chatHistory': row['chat_history'],
      'price': row['price'],
      'quantity': row['quantity'],
      'token': row['token'],
    };
  }

  Map<String, dynamic> _mapTxToSnake(CashTransaction tx) {
    return {
      'id': tx.id,
      'phone_number': tx.phoneNumber,
      'amount': tx.amount,
      'currency': tx.currency,
      'timestamp': tx.timestamp.toIso8601String(),
      'bybit_order_id': tx.bybitOrderId,
      'status': tx.status,
      'payment_method': tx.paymentMethod,
      'side': tx.side,
      'chat_history': tx.chatHistory,
      'price': tx.price,
      'quantity': tx.quantity,
      'token': tx.token,
    };
  }

  // ── Mobile Numbers ───────────────────────────────────────────────────────

  Future<void> addMobileNumber(MobileNumber number) async {
    try {
      await _supabase.from(_numbersTable).upsert(_mapNumberToSnake(number));
    } catch (e) {
      throw Exception('Error adding mobile number to Supabase: $e');
    }
  }

  Stream<List<MobileNumber>> streamMobileNumbers() {
    return _supabase.from(_numbersTable).stream(primaryKey: ['id']).map((rows) {
      return rows.map((row) => MobileNumber.fromMap(_mapNumberToCamel(row))).toList();
    });
  }

  Future<List<MobileNumber>> getMobileNumbers() async {
    try {
      final List<dynamic> rows = await _supabase.from(_numbersTable).select();
      return rows.map((row) => MobileNumber.fromMap(_mapNumberToCamel(row))).toList();
    } catch (e) {
      print('Warning: could not load mobile numbers from Supabase: $e');
      return [];
    }
  }

  Future<MobileNumber?> getDefaultNumber() async {
    final numbers = await getMobileNumbers();
    if (numbers.isEmpty) return null;
    final defaults = numbers.where((n) => n.isDefault).toList();
    return defaults.isNotEmpty ? defaults.first : numbers.first;
  }

  Future<void> setDefaultNumber(String numberId) async {
    try {
      // In Supabase we can do this in two queries
      await _supabase.from(_numbersTable).update({'is_default': false}).neq('id', numberId);
      await _supabase.from(_numbersTable).update({'is_default': true}).eq('id', numberId);
    } catch (e) {
      throw Exception('Error setting default number in Supabase: $e');
    }
  }

  Future<void> deleteMobileNumber(String numberId) async {
    try {
      await _supabase.from(_numbersTable).delete().eq('id', numberId);
    } catch (e) {
      throw Exception('Error deleting mobile number from Supabase: $e');
    }
  }

  // ── Transactions ─────────────────────────────────────────────────────────

  Future<Set<String>> getExistingBybitOrderIds() async {
    try {
      final List<dynamic> rows = await _supabase.from(_transactionsTable).select('bybit_order_id');
      return rows.map((r) => r['bybit_order_id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
    } catch (e) {
      print('Warning: could not pre-load order IDs from Supabase: $e');
      return {};
    }
  }

  Future<bool> addTransaction(CashTransaction transaction, {Set<String>? knownIds}) async {
    try {
      final orderId = transaction.bybitOrderId;
      if (orderId.isNotEmpty) {
        if (knownIds != null) {
          if (knownIds.contains(orderId)) return false;
        } else {
          final existing = await _supabase.from(_transactionsTable).select('id').eq('bybit_order_id', orderId).maybeSingle();
          if (existing != null) return false;
        }
      }

      await _supabase.from(_transactionsTable).upsert(_mapTxToSnake(transaction));
      knownIds?.add(orderId);

      // NOTE: DO NOT recalculate usage here.
      // Balances (in_total_used / out_total_used) are managed exclusively by
      // Supabase RPCs (process_bybit_order_sync, distribute_vf_cash, etc.).
      // Recalculating from the transactions table produces wrong results because
      // it misses DEPOSIT_TO_VFCASH, INTERNAL_VF_TRANSFER and other ledger-only entries.

      return true;
    } catch (e) {
      throw Exception('Error adding transaction to Supabase: $e');
    }
  }

  Stream<List<CashTransaction>> streamTransactionsForNumber(String phoneNumber) {
    return _supabase
        .from(_transactionsTable)
        .stream(primaryKey: ['id'])
        .eq('phone_number', phoneNumber)
        .map((rows) {
          final list = rows.map((row) => CashTransaction.fromMap(_mapTxToCamel(row))).toList();
          list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return list;
        });
  }

  Future<List<CashTransaction>> getTransactionsForNumber(String phoneNumber) async {
    try {
      final List<dynamic> rows = await _supabase.from(_transactionsTable).select().eq('phone_number', phoneNumber);
      final list = rows.map((row) => CashTransaction.fromMap(_mapTxToCamel(row))).toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    } catch (e) {
      throw Exception('Error fetching transactions from Supabase: $e');
    }
  }

  Stream<List<CashTransaction>> streamAllTransactions() {
    return _supabase.from(_transactionsTable).stream(primaryKey: ['id']).map((rows) {
      final list = rows.map((row) => CashTransaction.fromMap(_mapTxToCamel(row))).toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    });
  }

  Future<List<CashTransaction>> getAllTransactions() async {
    try {
      final List<dynamic> rows = await _supabase.from(_transactionsTable).select();
      final list = rows.map((row) => CashTransaction.fromMap(_mapTxToCamel(row))).toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    } catch (e) {
      print('Warning: could not load transactions from Supabase: $e');
      return [];
    }
  }

  // DISABLED: Do not recalculate from transactions table.
  // Balances are authoritative from the financial_ledger via Supabase RPCs.
  // Calling this would overwrite correct ledger-based values with incomplete
  // transaction-table data (which misses DEPOSIT_TO_VFCASH, INTERNAL_VF_TRANSFER, etc.).
  Future<void> recalculateUsageForNumber(String phoneNumber) async {
    // No-op: intentionally disabled to prevent balance corruption.
  }

  Future<void> _updateNumberUsage(String phoneNumber) async {
    // No-op: intentionally disabled to prevent balance corruption.
  }

  // ── Sync ─────────────────────────────────────────────────────────────────

  Future<int> getLastSyncedOrderTimestamp() async {
    try {
      final response = await _supabase.from(_syncTable).select('last_synced_order_ts').eq('id', 1).maybeSingle();
      return response != null ? (response['last_synced_order_ts'] as int) : 0;
    } catch (e) {
      return 0;
    }
  }

  Future<void> saveLastSyncedOrderTimestamp(int ts) async {
    try {
      await _supabase.from(_syncTable).upsert({'id': 1, 'last_synced_order_ts': ts});
    } catch (e) {
      print('Error saving lastSyncedOrderTs to Supabase: $e');
    }
  }

  Future<DateTime?> getLastSyncTime() async {
    try {
      final response = await _supabase.from(_syncTable).select('last_sync_time').eq('id', 1).maybeSingle();
      if (response == null || response['last_sync_time'] == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(response['last_sync_time'] as int);
    } catch (e) {
      return null;
    }
  }

  Future<void> saveLastSyncTime(int ms) async {
    try {
      await _supabase.from(_syncTable).upsert({'id': 1, 'last_sync_time': ms});
    } catch (e) {
      print('Error saving lastSyncTime to Supabase: $e');
    }
  }

  Future<int> getLastSyncTimestamp() => getLastSyncedOrderTimestamp();
  Future<void> updateLastSyncTimestamp(int ts) => saveLastSyncedOrderTimestamp(ts);

  Future<void> resetDailyUsage() async {
    try {
      await _supabase.from(_numbersTable).update({'in_daily_used': 0, 'out_daily_used': 0});
    } catch (e) {
      print('Error resetting daily usage in Supabase: $e');
    }
  }

  Future<void> resetMonthlyUsage() async {
    try {
      await _supabase.from(_numbersTable).update({'in_monthly_used': 0, 'out_monthly_used': 0});
    } catch (e) {
      print('Error resetting monthly usage in Supabase: $e');
    }
  }

  Future<void> deleteAllTransactions() async {
    try {
      // In Supabase, we use an RPC for safety or delete all
      await _supabase.from(_transactionsTable).delete().neq('id', '00000000-0000-0000-0000-000000000000');
      await _supabase.from(_syncTable).update({'last_synced_order_ts': 0, 'last_sync_time': null}).eq('id', 1);
      await resetDailyUsage();
      await resetMonthlyUsage();
    } catch (e) {
      throw Exception('Error deleting all transactions from Supabase: $e');
    }
  }

  Future<void> resetSyncMarkers() async {
    try {
      await _supabase.from(_syncTable).update({'last_synced_order_ts': 0, 'last_sync_time': null}).eq('id', 1);
    } catch (e) {
      print('Error resetting sync markers in Supabase: $e');
    }
  }
}
