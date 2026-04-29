import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../models/models.dart';
import '../services/database_service.dart';

class SyncResult {
  final int added;
  final int skipped; 
  final String? error;
  const SyncResult({this.added = 0, this.skipped = 0, this.error});
  bool get isSuccess => error == null;
  @override
  String toString() {
    if (error != null) return 'Sync failed: $error';
    return 'Added $added order${added == 1 ? '' : 's'}${skipped > 0 ? ', skipped $skipped duplicate${skipped == 1 ? '' : 's'}' : ''}';
  }
}

class AppProvider extends ChangeNotifier {
  bool _isSyncing = false;
  final DatabaseService _dbService = DatabaseService();
  final sb.SupabaseClient _supabase = sb.Supabase.instance.client;

  List<MobileNumber> _mobileNumbers = [];
  List<CashTransaction> _transactions = [];
  MobileNumber? _defaultNumber;
  bool _isLoading = false;
  String? _error;

  bool _hasApiCredentials = false;
  DateTime? _lastSyncTime;      
  int _lastSyncedOrderTs = 0;   
  String _syncStatus = '';      
  bool _isLiveSyncEnabled = false;
  Timer? _liveSyncTimer;
  double _collectorVfDepositFeePer1000 = 7.0;
  String? _publicDefaultNumberId;
  String? _publicDefaultNumberPhone;
  List<Map<String, String>> _publicVfNumbers = [];
  
  String _vfStartDate = '2026-03-18';
  String _instaPayStartDate = '2026-04-09';

  StreamSubscription? _numbersSub;
  StreamSubscription? _transactionsSub;
  StreamSubscription? _syncDataSub;
  StreamSubscription? _systemConfigSub;

  List<MobileNumber> get mobileNumbers => _mobileNumbers;
  List<CashTransaction> get transactions => _transactions;
  MobileNumber? get defaultNumber => _defaultNumber;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasApiCredentials => _hasApiCredentials;
  DateTime? get lastSyncTime => _lastSyncTime;
  String get syncStatus => _syncStatus;
  bool get isLiveSyncEnabled => _isLiveSyncEnabled;
  double get collectorVfDepositFeePer1000 => _collectorVfDepositFeePer1000;
  String? get publicDefaultNumberId => _publicDefaultNumberId;
  String? get publicDefaultNumberPhone => _publicDefaultNumberPhone;
  List<Map<String, String>> get publicVfNumbers => _publicVfNumbers;
  String get vfStartDate => _vfStartDate;
  String get instaPayStartDate => _instaPayStartDate;

  // Callbacks for Bybit Sync (to bridge with DistributionProvider logic)
  Future<void> Function({
    required String bybitOrderId,
    required double usdtQuantity,
    required double egpAmount,
    required double usdtPrice,
    required DateTime timestamp,
  })? _onBuyOrderCallback;

  Future<void> Function({
    required String bybitOrderId,
    required double egpAmount,
    required double usdtQuantity,
    required double usdtPrice,
    required String paymentMethod,
    required String? vfNumberId,
    required String vfNumberLabel,
    required String createdByUid,
    required DateTime timestamp,
  })? _onSellOrderCallback;

  void setBuyOrderCallback(Future<void> Function({
    required String bybitOrderId,
    required double usdtQuantity,
    required double egpAmount,
    required double usdtPrice,
    required DateTime timestamp,
  }) callback) {
    _onBuyOrderCallback = callback;
  }

  void setSellOrderCallback(Future<void> Function({
    required String bybitOrderId,
    required double egpAmount,
    required double usdtQuantity,
    required double usdtPrice,
    required String paymentMethod,
    required String? vfNumberId,
    required String vfNumberLabel,
    required String createdByUid,
    required DateTime timestamp,
  }) callback) {
    _onSellOrderCallback = callback;
  }

  AppProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _initializeListeners();
    } catch (e) {
      debugPrint('Initialization error: $e');
      _error = 'Could not connect to Supabase.';
      notifyListeners();
    }
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  void _initializeListeners() {
    _numbersSub?.cancel();
    _numbersSub = _dbService.streamMobileNumbers().listen((numbers) {
      _mobileNumbers = numbers;
      _mobileNumbers.sort((a, b) {
        if (a.isDefault == b.isDefault) return a.phoneNumber.compareTo(b.phoneNumber);
        return a.isDefault ? -1 : 1;
      });
      _defaultNumber = _mobileNumbers.isEmpty ? null : _mobileNumbers.where((n) => n.isDefault).firstOrNull ?? _mobileNumbers.first;
      pushDefaultNumberToPublic();
      notifyListeners();
    });

    _transactionsSub?.cancel();
    _transactionsSub = _dbService.streamAllTransactions().listen((txs) {
      _transactions = txs;
      notifyListeners();
    });

    _syncDataSub?.cancel();
    _syncDataSub = _supabase.from('sync_state').stream(primaryKey: ['id']).listen((rows) {
      if (rows.isNotEmpty) {
        final data = rows.first;
        _lastSyncedOrderTs = data['last_synced_order_ts'] as int? ?? 0;
        final ms = data['last_sync_time'] as int?;
        _lastSyncTime = ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
      }
      notifyListeners();
    });

    _systemConfigSub?.cancel();
    _systemConfigSub = _supabase.from('system_config').stream(primaryKey: ['key']).listen((rows) {
      for (final row in rows) {
        final key = row['key'];
        final val = row['value'];
        if (key == 'operation_settings') {
          _collectorVfDepositFeePer1000 = _asDouble(val['collectorVfDepositFeePer1000']);
          _publicDefaultNumberId = val['defaultVfNumberId']?.toString();
          _publicDefaultNumberPhone = val['defaultVfNumberPhone']?.toString();
          if (val['vfNumbers'] is List) {
            _publicVfNumbers = (val['vfNumbers'] as List).map((m) => {
              'id': m['id']?.toString() ?? '',
              'phoneNumber': m['phoneNumber']?.toString() ?? '',
            }).toList();
          }
        } else if (key == 'sync_config') {
          _isLiveSyncEnabled = val['enabled'] == true;
        } else if (key == 'bybit_metadata') {
          _hasApiCredentials = val['configured'] == true;
        } else if (key == 'module_start_dates') {
          _vfStartDate = val['vf']?.toString() ?? '2026-03-18';
          _instaPayStartDate = val['instapay']?.toString() ?? '2026-04-09';
        }
      }
      notifyListeners();
    });
  }

  Future<void> pushDefaultNumberToPublic({MobileNumber? override}) async {
    final numToPush = override ?? _defaultNumber;
    final vfList = _mobileNumbers.map((n) => {'id': n.id, 'phoneNumber': n.phoneNumber}).toList();
    final data = {
      'defaultVfNumberId': numToPush?.id,
      'defaultVfNumberPhone': numToPush?.phoneNumber,
      'vfNumbers': vfList,
      'collectorVfDepositFeePer1000': _collectorVfDepositFeePer1000,
    };
    await _supabase.from('system_config').upsert({'key': 'operation_settings', 'value': data});
  }

  @override
  void dispose() {
    _liveSyncTimer?.cancel();
    _numbersSub?.cancel();
    _transactionsSub?.cancel();
    _syncDataSub?.cancel();
    _systemConfigSub?.cancel();
    super.dispose();
  }

  Future<void> saveApiCredentials(String apiKey, String apiSecret) async {
    await _supabase.functions.invoke('manual-sync-bybit', body: {
      'apiKey': apiKey,
      'apiSecret': apiSecret,
      'action': 'set_credentials'
    });
  }

  Future<void> clearApiCredentials() async {
    await _supabase.from('system_config').delete().eq('key', 'bybit_metadata');
  }

  Future<void> saveCollectorVfDepositFeePer1000(double feePer1000) async {
    _collectorVfDepositFeePer1000 = feePer1000;
    await pushDefaultNumberToPublic();
  }

  Future<void> saveModuleStartDates(String vf, String insta) async {
    await _supabase.from('system_config').upsert({
      'key': 'module_start_dates',
      'value': {'vf': vf, 'instapay': insta}
    });
  }

  Future<SyncResult> syncOrders({DateTime? fromDate, bool isSilent = false}) async {
    if (_isSyncing) return const SyncResult(error: 'Sync in progress');
    _isSyncing = true;
    if (!isSilent) { _isLoading = true; _syncStatus = 'Syncing...'; notifyListeners(); }
    try {
      final response = await _supabase.functions.invoke('manual-sync-bybit', body: {
        if (fromDate != null) 'beginTime': fromDate.millisecondsSinceEpoch.toString(),
      });
      final data = response.data;
      return SyncResult(added: data['added'] ?? 0, skipped: data['skipped'] ?? 0);
    } catch (e) {
      return SyncResult(error: e.toString());
    } finally {
      _isSyncing = false;
      _isLoading = false;
      _syncStatus = ''; // Clear status so the progress bar disappears
      notifyListeners();
    }
  }

  Future<void> toggleLiveSync(bool enabled) async {
    await _supabase.from('system_config').upsert({
      'key': 'sync_config',
      'value': {'enabled': enabled}
    });
  }

  Future<void> loadMobileNumbers() async {
    // Re-initialize listeners or manually fetch if needed
    _initializeListeners();
  }

  Future<List<CashTransaction>> getTransactionsForNumber(String phoneNumber) async {
    return await _dbService.getTransactionsForNumber(phoneNumber);
  }

  Future<void> addMobileNumber({
    required String phoneNumber, String? name, required double initialBalance,
    required double inDailyLimit, required double inMonthlyLimit,
    required double outDailyLimit, required double outMonthlyLimit,
  }) async {
    final number = MobileNumber(
      id: const Uuid().v4(), phoneNumber: phoneNumber, name: name, initialBalance: initialBalance,
      inDailyLimit: inDailyLimit, inMonthlyLimit: inMonthlyLimit,
      outDailyLimit: outDailyLimit, outMonthlyLimit: outMonthlyLimit,
      isDefault: _mobileNumbers.isEmpty, createdAt: DateTime.now(), lastUpdatedAt: DateTime.now(),
    );
    await _dbService.addMobileNumber(number);
  }

  Future<void> updateMobileNumber(MobileNumber updatedNumber) async => await _dbService.addMobileNumber(updatedNumber);
  Future<void> setDefaultNumber(String numberId) async => await _dbService.setDefaultNumber(numberId);
  Future<void> deleteMobileNumber(String numberId) async => await _dbService.deleteMobileNumber(numberId);
  // DISABLED: recalculateAllUsage is a no-op - balances are managed by Supabase RPCs only.
  Future<void> recalculateAllUsage() async {
    // Intentionally empty - do not recalculate from transactions table.
    // Balances come from the financial_ledger via process_bybit_order_sync, distribute_vf_cash, etc.
  }
  Future<void> deleteAllTransactions() async {
    await _dbService.deleteAllTransactions();
    // Do NOT call recalculateAllUsage after deleting - balances are ledger-based.
  }
  Future<void> resetSyncMarkers() async => await _dbService.resetSyncMarkers();

  // Limit Helpers
  double getInDailyRemaining(MobileNumber n) => (n.inDailyLimit - n.inDailyUsed).clamp(0, double.infinity);
  double getOutDailyRemaining(MobileNumber n) => (n.outDailyLimit - n.outDailyUsed).clamp(0, double.infinity);
  double getInMonthlyRemaining(MobileNumber n) => (n.inMonthlyLimit - n.inMonthlyUsed).clamp(0, double.infinity);
  double getOutMonthlyRemaining(MobileNumber n) => (n.outMonthlyLimit - n.outMonthlyUsed).clamp(0, double.infinity);
  bool isInDailyLimitExceeded(MobileNumber n) => n.inDailyUsed >= n.inDailyLimit;
  bool isOutDailyLimitExceeded(MobileNumber n) => n.outDailyUsed >= n.outDailyLimit;
  double getInDailyUsagePercentage(MobileNumber n) => n.inDailyLimit == 0 ? 0 : (n.inDailyUsed / n.inDailyLimit).clamp(0, 1);
  double getOutDailyUsagePercentage(MobileNumber n) => n.outDailyLimit == 0 ? 0 : (n.outDailyUsed / n.outDailyLimit).clamp(0, 1);
}
