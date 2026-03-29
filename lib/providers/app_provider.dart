import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/models.dart';
import '../services/database_service.dart';

class SyncResult {
  final int added;
  final int skipped; // duplicates
  final String? error;

  const SyncResult({this.added = 0, this.skipped = 0, this.error});

  bool get isSuccess => error == null;

  @override
  String toString() {
    if (error != null) return 'Sync failed: $error';
    return 'Added $added order${added == 1 ? '' : 's'}'
        '${skipped > 0 ? ', skipped $skipped duplicate${skipped == 1 ? '' : 's'}' : ''}';
  }
}

class AppProvider extends ChangeNotifier {
  bool _isInit = false;
  bool _isSyncing = false;

  final DatabaseService _dbService = DatabaseService();

  List<MobileNumber> _mobileNumbers = [];
  List<CashTransaction> _transactions = [];
  MobileNumber? _defaultNumber;
  bool _isLoading = false;
  String? _error;

  // Sync state
  bool _hasApiCredentials = false;
  DateTime? _lastSyncTime;      // when we last ran a sync (for display)
  int _lastSyncedOrderTs = 0;   // createTime of newest order synced (for next beginTime)
  String _syncStatus = '';      // live progress text e.g. "Fetching page 2..."
  bool _isLiveSyncEnabled = false;
  Timer? _liveSyncTimer;
  double _collectorVfDepositFeePer1000 = 7.0;

  // ── Getters ───────────────────────────────────────────────────────────────
  // ─── Real-Time Stream Subscriptions ───────────────────────────────────────
  StreamSubscription<List<MobileNumber>>? _numbersSub;
  StreamSubscription<List<CashTransaction>>? _transactionsSub;
  StreamSubscription<DatabaseEvent>? _syncDataSub;
  StreamSubscription<DatabaseEvent>? _bybitMetadataSub;
  StreamSubscription<DatabaseEvent>? _operationSettingsSub;

  List<MobileNumber> get mobileNumbers => _mobileNumbers;
  List<CashTransaction> get transactions => _transactions;
  MobileNumber? get defaultNumber => _defaultNumber;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasApiCredentials => _hasApiCredentials;
  DateTime? get lastSyncTime => _lastSyncTime;
  String get syncStatus => _syncStatus;
  bool get isLiveSyncEnabled => _isLiveSyncEnabled;
  bool get useServerSync => true;
  double get collectorVfDepositFeePer1000 => _collectorVfDepositFeePer1000;

  // Callback to trigger Bank logic in DistributionProvider
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

  void setBuyOrderCallback(
      Future<void> Function({
        required String bybitOrderId,
        required double usdtQuantity,
        required double egpAmount,
        required double usdtPrice,
        required DateTime timestamp,
      }) callback) {
    _onBuyOrderCallback = callback;
  }

  void setSellOrderCallback(
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
      }) callback) {
    _onSellOrderCallback = callback;
  }

  AppProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _initializeListeners();
      await _loadLiveSyncState();
    } catch (e) {
      debugPrint('Initialization error (non-fatal): $e');
      _error = 'Could not connect to database. Check your internet connection.';
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
        if (a.isDefault == b.isDefault) {
          return a.phoneNumber.compareTo(b.phoneNumber);
        }
        return a.isDefault ? -1 : 1;
      });
      _defaultNumber = _mobileNumbers.isEmpty
          ? null
          : _mobileNumbers.firstWhere((n) => n.isDefault,
              orElse: () => _mobileNumbers.first);
      notifyListeners();
    });

    _transactionsSub?.cancel();
    _transactionsSub = _dbService.streamAllTransactions().listen((txs) {
      _transactions = txs;
      notifyListeners();
    });

    _syncDataSub?.cancel();
    _syncDataSub = FirebaseDatabase.instance.ref('sync_data').onValue.listen((event) {
      final snap = event.snapshot;
      if (snap.exists && snap.value != null && snap.value is Map) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _lastSyncedOrderTs = data['lastSyncedOrderTs'] as int? ?? 0;
        final ms = data['lastSyncTime'] as int?;
        _lastSyncTime = ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
      } else {
        _lastSyncedOrderTs = 0;
        _lastSyncTime = null;
      }
      notifyListeners();
    });

    _bybitMetadataSub?.cancel();
    _bybitMetadataSub = FirebaseDatabase.instance
        .ref('system/api_credentials/bybit_metadata')
        .onValue
        .listen((event) {
      final snap = event.snapshot;
      if (snap.exists && snap.value is Map) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _hasApiCredentials = data['configured'] == true;
      } else {
        _hasApiCredentials = false;
      }
      notifyListeners();
    });

    _operationSettingsSub?.cancel();
    _operationSettingsSub = FirebaseDatabase.instance
        .ref('system/operation_settings')
        .onValue
        .listen((event) {
      final snap = event.snapshot;
      if (snap.exists && snap.value is Map) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _collectorVfDepositFeePer1000 =
            _asDouble(data['collectorVfDepositFeePer1000']);
      } else {
        _collectorVfDepositFeePer1000 = 7.0;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _liveSyncTimer?.cancel();
    _numbersSub?.cancel();
    _transactionsSub?.cancel();
    _syncDataSub?.cancel();
    _bybitMetadataSub?.cancel();
    _operationSettingsSub?.cancel();
    _syncConfigSub?.cancel();
    super.dispose();
  }


  // ── API Credentials ───────────────────────────────────────────────────────

  Future<void> saveApiCredentials(String apiKey, String apiSecret) async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-east1');
    await functions.httpsCallable('setBybitCredentials').call({
      'apiKey': apiKey,
      'apiSecret': apiSecret,
    });
    _hasApiCredentials = true;
    notifyListeners();
  }

  Future<void> clearApiCredentials() async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-east1');
    await functions.httpsCallable('clearBybitCredentials').call();
    _hasApiCredentials = false;
    notifyListeners();
  }

  Future<void> saveCollectorVfDepositFeePer1000(double feePer1000) async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-east1');
    await functions.httpsCallable('setCollectorVfDepositFeePer1000').call({
      'feePer1000': feePer1000,
    });
    _collectorVfDepositFeePer1000 = feePer1000;
    notifyListeners();
  }

  Future<SyncResult> _syncOrdersServer({DateTime? fromDate, bool isSilent = false}) async {
    if (_isSyncing) return const SyncResult(error: 'Sync in progress');
    _isSyncing = true;
    if (!isSilent) {
      _isLoading = true;
      _syncStatus = 'Requesting server sync...';
      notifyListeners();
    }

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-east1');

      // Build payload — include beginTime only if a custom fromDate was chosen
      Map<String, dynamic>? payload;
      if (fromDate != null) {
        final utcDate = DateTime.utc(fromDate.year, fromDate.month, fromDate.day);
        payload = {'beginTime': utcDate.millisecondsSinceEpoch.toString()};
        _syncStatus = 'Syncing from ${fromDate.day}/${fromDate.month}/${fromDate.year}...';
        if (!isSilent) notifyListeners();
      }

      final result = await functions.httpsCallable('manualSyncBybit').call(payload);

      final Map<String, dynamic> data = Map<String, dynamic>.from(result.data as Map);
      final added = data['added'] as int? ?? 0;
      final skipped = data['skipped'] as int? ?? 0;

      // Data updates are real-time via Firebase, but we reload to be sure
      await loadAllTransactions();
      await loadMobileNumbers();

      _lastSyncTime = DateTime.now();
      _syncStatus = '';
      return SyncResult(added: added, skipped: skipped);
    } catch (e) {
      _syncStatus = '';
      return SyncResult(error: e.toString());
    } finally {
      _isSyncing = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Live Sync Monitoring ────────────────────────────────────────────────
  
  StreamSubscription? _syncConfigSub;

  Future<void> _loadLiveSyncState() async {
    // Listen to Firebase for the central sync switch without overriding it on startup.
    _syncConfigSub?.cancel();
    _syncConfigSub = FirebaseDatabase.instance.ref('system/sync_config').onValue.listen((event) {
      final snap = event.snapshot;
      if (snap.exists && snap.value is Map) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _isLiveSyncEnabled = data['enabled'] == true;
      } else {
        _isLiveSyncEnabled = false;
      }
      notifyListeners();
    });
  }

  Future<void> toggleServerSync(bool enabled) async {
    await FirebaseDatabase.instance.ref('system/sync_config/enabled').set(enabled);
    notifyListeners();
  }

  void _startLiveSyncTimer() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      syncOrders(isSilent: true);
    });
    debugPrint('Sync: Live Monitoring STARTED (30s interval) from TS $_lastSyncedOrderTs');
  }

  void _stopLiveSyncTimer() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
    debugPrint('Sync: Live Monitoring STOPPED');
  }

  Future<void> toggleLiveSync(bool enabled) async {
    await FirebaseDatabase.instance.ref('system/sync_config/enabled').set(enabled);
  }

  //  dispose method moved to top

  // ── Mobile Numbers ────────────────────────────────────────────────────────

  Future<void> loadMobileNumbers() async {
    // Deprecated: Now handled automatically via real-time stream `_initializeListeners`
  }

  Future<void> addMobileNumber({
    required String phoneNumber,
    required double initialBalance,
    required double inDailyLimit,
    required double inMonthlyLimit,
    required double outDailyLimit,
    required double outMonthlyLimit,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final number = MobileNumber(
        id: const Uuid().v4(),
        phoneNumber: phoneNumber,
        initialBalance: initialBalance,
        inDailyLimit: inDailyLimit,
        inMonthlyLimit: inMonthlyLimit,
        outDailyLimit: outDailyLimit,
        outMonthlyLimit: outMonthlyLimit,
        isDefault: _mobileNumbers.isEmpty,
        createdAt: DateTime.now(),
        lastUpdatedAt: DateTime.now(),
      );
      await _dbService.addMobileNumber(number);
      await loadMobileNumbers();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setDefaultNumber(String numberId) async {
    try {
      await _dbService.setDefaultNumber(numberId);
      await loadMobileNumbers();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteMobileNumber(String numberId) async {
    try {
      await _dbService.deleteMobileNumber(numberId);
      await loadMobileNumbers();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Recalculate dailyUsed / monthlyUsed for every number from actual
  /// stored transactions (filtered by today / this month).
  /// Call after reloading or deleting transactions so UI stays accurate.
  Future<void> recalculateAllUsage() async {
    try {
      for (final number in _mobileNumbers) {
        await _dbService.recalculateUsageForNumber(number.phoneNumber);
      }
      await loadMobileNumbers(); // reload so UI reflects new values
    } catch (e) {
      debugPrint('Error recalculating usage: $e');
    }
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  Future<void> loadAllTransactions() async {
    // Deprecated: Now handled automatically via real-time stream `_initializeListeners`
  }

  Future<List<CashTransaction>> getTransactionsForNumber(
      String phoneNumber) async {
    try {
      return await _dbService.getTransactionsForNumber(phoneNumber);
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteAllTransactions() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _dbService.deleteAllTransactions();
      _transactions.clear();
      _lastSyncedOrderTs = 0;
      await recalculateAllUsage();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> resetSyncMarkers() async {
    try {
      await _dbService.resetSyncMarkers();
      _lastSyncedOrderTs = 0;
      _lastSyncTime = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error resetting markers: $e');
    }
  }

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Unified sync method.
  ///
  /// [fromDate] — if provided, does a **full sync** from that date.
  ///              if null, does an **incremental sync** from the last synced order timestamp.
  ///
  /// Orders are always deduplicated by `bybitOrderId` before saving.
  Future<SyncResult> syncOrders({DateTime? fromDate, bool isSilent = false}) async {
    return _syncOrdersServer(fromDate: fromDate, isSilent: isSilent);
  }

  // ── Limit Helpers ─────────────────────────────────────────────────────────

  double getInDailyRemaining(MobileNumber n) =>
      (n.inDailyLimit - n.inDailyUsed).clamp(0, double.infinity);

  double getOutDailyRemaining(MobileNumber n) =>
      (n.outDailyLimit - n.outDailyUsed).clamp(0, double.infinity);

  double getInMonthlyRemaining(MobileNumber n) =>
      (n.inMonthlyLimit - n.inMonthlyUsed).clamp(0, double.infinity);

  double getOutMonthlyRemaining(MobileNumber n) =>
      (n.outMonthlyLimit - n.outMonthlyUsed).clamp(0, double.infinity);

  bool isInDailyLimitExceeded(MobileNumber n) =>
      n.inDailyUsed >= n.inDailyLimit;

  bool isOutDailyLimitExceeded(MobileNumber n) =>
      n.outDailyUsed >= n.outDailyLimit;

  bool isInMonthlyLimitExceeded(MobileNumber n) =>
      n.inMonthlyUsed >= n.inMonthlyLimit;

  bool isOutMonthlyLimitExceeded(MobileNumber n) =>
      n.outMonthlyUsed >= n.outMonthlyLimit;

  double getInDailyUsagePercentage(MobileNumber n) =>
      n.inDailyLimit == 0 ? 0 : (n.inDailyUsed / n.inDailyLimit).clamp(0, 1);

  double getOutDailyUsagePercentage(MobileNumber n) =>
      n.outDailyLimit == 0 ? 0 : (n.outDailyUsed / n.outDailyLimit).clamp(0, 1);

  double getInMonthlyUsagePercentage(MobileNumber n) => n.inMonthlyLimit == 0
      ? 0
      : (n.inMonthlyUsed / n.inMonthlyLimit).clamp(0, 1);

  double getOutMonthlyUsagePercentage(MobileNumber n) => n.outMonthlyLimit == 0
      ? 0
      : (n.outMonthlyUsed / n.outMonthlyLimit).clamp(0, 1);
}
