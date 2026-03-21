import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/bybit_service.dart';

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
  BybitService? _bybitService;

  List<MobileNumber> _mobileNumbers = [];
  List<CashTransaction> _transactions = [];
  MobileNumber? _defaultNumber;
  bool _isLoading = false;
  String? _error;

  // Sync state
  String _apiKey = '';
  String _apiSecret = '';
  DateTime? _lastSyncTime;      // when we last ran a sync (for display)
  int _lastSyncedOrderTs = 0;   // createTime of newest order synced (for next beginTime)
  String _syncStatus = '';      // live progress text e.g. "Fetching page 2..."
  bool _isLiveSyncEnabled = false;
  Timer? _liveSyncTimer;

  bool _useServerSync = true; // Default to server sync now

  // ── Getters ───────────────────────────────────────────────────────────────
  List<MobileNumber> get mobileNumbers => _mobileNumbers;
  List<CashTransaction> get transactions => _transactions;
  MobileNumber? get defaultNumber => _defaultNumber;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasApiCredentials => _apiKey.isNotEmpty && _apiSecret.isNotEmpty;
  DateTime? get lastSyncTime => _lastSyncTime;
  String get syncStatus => _syncStatus;
  bool get isLiveSyncEnabled => _isLiveSyncEnabled;
  bool get useServerSync => _useServerSync;

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
      await _loadApiCredentials();
      await loadMobileNumbers();
      await loadAllTransactions();
      _lastSyncedOrderTs = await _dbService.getLastSyncedOrderTimestamp();
      _lastSyncTime = await _dbService.getLastSyncTime();
      await _loadLiveSyncState();
    } catch (e) {
      print('Initialization error (non-fatal): $e');
      _error = 'Could not connect to database. Check your internet connection.';
      notifyListeners();
    }
  }

  // ── API Credentials ───────────────────────────────────────────────────────

  Future<void> _loadApiCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _apiKey = prefs.getString('bybit_api_key') ?? '';
      _apiSecret = prefs.getString('bybit_api_secret') ?? '';
      _initBybitService();
    } catch (e) {
      print('Error loading API credentials: $e');
    }
  }

  void _initBybitService() {
    if (_apiKey.isNotEmpty && _apiSecret.isNotEmpty) {
      _bybitService = BybitService(apiKey: _apiKey, apiSecret: _apiSecret);
    } else {
      _bybitService = null;
    }
  }

  Future<void> saveApiCredentials(String apiKey, String apiSecret) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bybit_api_key', apiKey);
    await prefs.setString('bybit_api_secret', apiSecret);

    // Also save to Firebase for server-side sync
    await FirebaseDatabase.instance.ref('system/api_credentials/bybit').set({
      'apiKey': apiKey,
      'apiSecret': apiSecret,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    _apiKey = apiKey;
    _apiSecret = apiSecret;
    _initBybitService();
    notifyListeners();
  }

  Future<void> clearApiCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bybit_api_key');
    await prefs.remove('bybit_api_secret');

    await FirebaseDatabase.instance.ref('system/api_credentials/bybit').remove();

    _apiKey = '';
    _apiSecret = '';
    _bybitService = null;
    notifyListeners();
  }

  Future<SyncResult> _syncOrdersServer({bool isSilent = false}) async {
    if (_isSyncing) return const SyncResult(error: 'Sync in progress');
    _isSyncing = true;
    if (!isSilent) {
      _isLoading = true;
      _syncStatus = 'Requesting server sync...';
      notifyListeners();
    }

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-east1');
      final result = await functions.httpsCallable('manualSyncBybit').call();

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
  
  Future<void> _loadLiveSyncState() async {
    final prefs = await SharedPreferences.getInstance();
    _isLiveSyncEnabled = prefs.getBool('live_sync_enabled') ?? false;
    _useServerSync = prefs.getBool('use_server_sync') ?? true;
    if (_isLiveSyncEnabled && !_useServerSync) {
      _startLiveSyncTimer();
    }
  }

  Future<void> toggleServerSync(bool enabled) async {
    _useServerSync = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_server_sync', enabled);
    if (enabled) {
      _stopLiveSyncTimer();
    } else if (_isLiveSyncEnabled) {
      _startLiveSyncTimer();
    }
    notifyListeners();
  }

  void _startLiveSyncTimer() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      syncOrders(isSilent: true);
    });
    print('Sync: Live Monitoring STARTED (30s interval) from TS $_lastSyncedOrderTs');
  }

  void _stopLiveSyncTimer() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
    print('Sync: Live Monitoring STOPPED');
  }

  Future<void> toggleLiveSync(bool enabled) async {
    _isLiveSyncEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('live_sync_enabled', enabled);
    
    if (enabled) {
      // User requested: When activating live sync, only fetch orders from THIS MOMENT onwards.
      _lastSyncedOrderTs = DateTime.now().millisecondsSinceEpoch;
      await _dbService.saveLastSyncedOrderTimestamp(_lastSyncedOrderTs);
      
      _startLiveSyncTimer();
    } else {
      _stopLiveSyncTimer();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _liveSyncTimer?.cancel();
    super.dispose();
  }

  // ── Mobile Numbers ────────────────────────────────────────────────────────

  Future<void> loadMobileNumbers() async {
    try {
      _mobileNumbers = await _dbService.getMobileNumbers();
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
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
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
      print('Error recalculating usage: $e');
    }
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  Future<void> loadAllTransactions() async {
    try {
      _transactions = await _dbService.getAllTransactions();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
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
      await loadMobileNumbers(); // This also triggers recalculateUsage inside DB
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
      print('Error resetting markers: $e');
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
    if (_useServerSync) {
      return _syncOrdersServer(isSilent: isSilent);
    }

    if (_bybitService == null) {
      return const SyncResult(error: 'No API credentials. Set them in Settings.');
    }
    if (_defaultNumber == null) {
      return const SyncResult(error: 'No default number set. Add a number first.');
    }
    if (_isSyncing) {
      return const SyncResult(error: 'Sync already in progress. Please wait.');
    }
    
    _isSyncing = true;

    if (!isSilent) {
      _isLoading = true;
      _syncStatus = 'Starting sync…';
      _error = null;
      notifyListeners();
    }

    try {
      // 0. Ensure local clock is synced with Bybit to prevent HMAC timestamp rejection
      await _bybitService!.syncServerTime();

      // Determine beginTime
      int? beginTime;
      if (fromDate != null) {
        // Full sync from chosen date — UTC midnight of that day
        final utcDate = DateTime.utc(fromDate.year, fromDate.month, fromDate.day);
        beginTime = utcDate.millisecondsSinceEpoch;
        
        final displayDate = _fmtDate(fromDate);
        print('Sync: Starting FULL SYNC from $displayDate (UTC: $utcDate, ms: $beginTime)');
        _syncStatus = 'Full Sync from $displayDate…';
        
        // IMPORTANT: For a full sync, we should ignore the local markers
        // to ensure we don't accidentally skip anything if markers were ahead.
      } else if (_lastSyncedOrderTs > 0) {
        // Incremental — start from 1ms after the last order we saved
        beginTime = _lastSyncedOrderTs + 1;
        print('Sync: Starting INCREMENTAL sync from TS $beginTime');
        _syncStatus = 'Checking for new orders…';
      } else {
        // No history — fetch last 30 days by default
        final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
        beginTime = thirtyDaysAgo.millisecondsSinceEpoch;
        print('Sync: Starting DEFAULT sync (last 30 days) from ${_fmtDate(thirtyDaysAgo)}');
        _syncStatus = 'First sync — fetching last 30 days…';
      }
      if (!isSilent) notifyListeners();

      // Fetch all pages
      print('Sync: Starting fetch with beginTime=$beginTime (${beginTime != null ? DateTime.fromMillisecondsSinceEpoch(beginTime) : 'none'})');
      
      final orders = await _bybitService!.getAllOrdersSince(
        beginTime: beginTime,
        onProgress: (page, fetched) {
          _syncStatus = 'Fetching page $page… ($fetched orders so far)';
          if (!isSilent) notifyListeners();
        },
      );

      if (!isSilent) {
        print('Sync: Fetched ${orders.length} orders total from Bybit.');
        _syncStatus = 'Fetching full order details for accuracy…';
        notifyListeners();
      }

      // Fetch high-fidelity details for ALL fetched orders to get accurate paymentMethod.
      // IMPORTANT: If getOrderById fails/returns null, fall back to the original order
      // so we never lose a BUY order just because the detail endpoint timed out.
      final detailedOrders = <BybitOrder>[];
      const chunkSize = 10;
      for (var i = 0; i < orders.length; i += chunkSize) {
        final chunk = orders.sublist(i, i + chunkSize > orders.length ? orders.length : i + chunkSize);
        final results = await Future.wait(chunk.map((o) => _bybitService!.getOrderById(o.orderId)));
        for (var j = 0; j < chunk.length; j++) {
          // Use detailed result if available, otherwise fall back to original order
          detailedOrders.add(results[j] ?? chunk[j]);
        }
      }

      if (!isSilent) {
        print('Sync: High-fidelity details fetched for ${detailedOrders.length} orders.');
        _syncStatus = 'Saving ${detailedOrders.length} orders to database…';
        notifyListeners();
      }

      int added = 0;
      int skipped = 0;
      int notVodaMethod = 0; // skipped because payment mode wasn't Voda
      int notVodaChat = 0;   // skipped because no Voda number found in chat

      final knownNumbers = _mobileNumbers.map((n) => n.phoneNumber).toList();
      print('Sync: Starting assignment loop. Known numbers in app: $knownNumbers');

      for (int i = 0; i < detailedOrders.length; i++) {
        final order = detailedOrders[i];
        
        // Final sanity check before processing
        // We must check if the order is genuinely older than the requested beginTime,
        // but we allow equal timestamps because an order might have been created EXACTLY
        // on the millisecond of beginTime.
        if (beginTime != null && order.createTime.millisecondsSinceEpoch < beginTime - 1000) {
           print('Sync: Skipping order ${order.orderId} - Outside date window (${order.createTime.millisecondsSinceEpoch} < $beginTime).');
           continue;
        }
        // Skip non-EGP orders
        if (order.currency.toUpperCase() != 'EGP') {
           print('Sync: Skipping order ${order.orderId} - Fiat currency is not EGP (${order.currency}).');
           continue;
        }

        // 1. Identification
        final pm = order.paymentMethod.toLowerCase();
        final isVoda = pm.contains('vodafone') || pm.contains('voda');
        final isBankTransfer = pm.contains('instapay') || pm.contains('bank transfer') || pm.contains('bank');
        final sideStr = order.side == 0 ? 'BUY' : 'SELL';

        if (!isSilent) {
          _syncStatus =
              'Order ${i + 1}/${detailedOrders.length} [$sideStr]: "${order.paymentMethod}" — syncing all data…';
          notifyListeners();
        }

        // Always update the newest timestamp seen
        if (order.createTime.millisecondsSinceEpoch > _lastSyncedOrderTs) {
          _lastSyncedOrderTs = order.createTime.millisecondsSinceEpoch;
        }

        // 2. Scan chat/terms for assignment
        String? matchedNumber;
        if (order.orderId.isNotEmpty && knownNumbers.isNotEmpty) {
          matchedNumber = await _bybitService!.findPhoneNumberInChat(
            order,
            knownNumbers,
          );
        }

        // 3. Fetch full chat history for the database mirror
        String chatSummary = '';
        if (order.orderId.isNotEmpty) {
          chatSummary = await _bybitService!.getChatSummary(order.orderId);
        }

        if (matchedNumber == null) {
          // No match found in chat or terms.
          print('Sync: No match for $sideStr order ${order.orderId}. Saving as Unassigned.');
          notVodaChat++;
        } else {
           print('Sync: Matched order ${order.orderId} to number $matchedNumber.');
        }

        // Handle BUY vs SELL logic separately
        if (order.side == 0) {
          // BUY USDT: We send EGP from bank, receive USDT
          if (isBankTransfer) {
             print('Sync: Processing BUY order ${order.orderId} via ${order.paymentMethod} (Bank/Instapay).');
          } else {
             print('Sync: Processing BUY order ${order.orderId} via ${order.paymentMethod}.');
          }
          
          // 1. Record transaction with or without a matched number
          final tx = CashTransaction(
            id: const Uuid().v4(),
            phoneNumber: matchedNumber,
            amount: order.amount,
            currency: order.currency.isEmpty ? 'EGP' : order.currency,
            timestamp: order.createTime,
            bybitOrderId: order.orderId,
            status: 'completed',
            paymentMethod: order.paymentMethod,
            side: order.side,
            chatHistory: chatSummary,
            price: order.price,
            quantity: order.quantity,
            token: order.token,
          );

          final wasAdded = await _dbService.addTransaction(tx);
          if (wasAdded) {
             added++;
          } else {
             skipped++;
          }

          // 2. Trigger Bank deduction ONLY if it's explicitly a Bank Transfer / Instapay method
          // We call this even if wasAdded is false, because DistributionProvider handles its own
          // deduplication via the ledger. This ensures missed ledger entries are caught.
          if (isBankTransfer) {
              await _onBuyOrderCallback?.call(
                 bybitOrderId: order.orderId,
                 usdtQuantity: order.quantity,
                 egpAmount: order.amount,
                 usdtPrice: order.price,
                 timestamp: order.createTime,
              );
          }
          continue; // Done processing BUY order
        }

        // SELL USDT: We receive EGP into Vodafone Cash
        if (!isVoda) {
          print('Sync: Skipping order ${order.orderId} - Mode: "${order.paymentMethod}" is NOT Vodafone Cash.');
          notVodaMethod++;
          continue;
        }

        final tx = CashTransaction(
          id: const Uuid().v4(),
          phoneNumber: matchedNumber,
          amount: order.amount,
          currency: order.currency.isEmpty ? 'EGP' : order.currency,
          timestamp: order.createTime,
          bybitOrderId: order.orderId,
          status: 'completed',
          paymentMethod: order.paymentMethod,
          side: order.side,
          chatHistory: chatSummary,
          price: order.price,
          quantity: order.quantity,
          token: order.token,
        );

        final wasAdded = await _dbService.addTransaction(tx);
        if (wasAdded) {
          added++;
        } else {
          skipped++;
        }

        // Trigger SELL deduction logic (Vodafone Cash received)
        // We call this even if wasAdded is false, because DistributionProvider handles its own
        // deduplication via the ledger. This ensures missed ledger entries are caught.
        final matchedVf = _mobileNumbers.firstWhere(
          (n) => n.phoneNumber == matchedNumber,
          orElse: () => MobileNumber(id: 'unknown', phoneNumber: matchedNumber ?? 'unknown', isDefault: false, createdAt: DateTime.now())
        );
        
        await _onSellOrderCallback?.call(
          bybitOrderId: order.orderId,
          egpAmount: order.amount,
          usdtQuantity: order.quantity,
          usdtPrice: order.price,
          paymentMethod: order.paymentMethod,
          vfNumberId: matchedVf.id == 'unknown' ? null : matchedVf.id,
          vfNumberLabel: matchedVf.phoneNumber,
          createdByUid: 'system_sync',
          timestamp: order.createTime,
        );
      }

      print('Sync Result: $added total records, $skipped duplicates. (Vodafone: ${added - notVodaMethod}, Other: $notVodaMethod, Unassigned: $notVodaChat)');

      // Persist sync metadata
      _lastSyncTime = DateTime.now();
      await _dbService.saveLastSyncedOrderTimestamp(_lastSyncedOrderTs);
      await _dbService.saveLastSyncTime(_lastSyncTime!.millisecondsSinceEpoch);

      // Reload UI data
      await loadAllTransactions();
      await loadMobileNumbers();

      _syncStatus = '';
      if (!isSilent) notifyListeners();
      return SyncResult(added: added, skipped: skipped);
    } catch (e) {
      _error = e.toString();
      _syncStatus = '';
      if (!isSilent) notifyListeners();
      return SyncResult(error: e.toString());
    } finally {
      _isSyncing = false;
      if (!isSilent) {
        _isLoading = false;
        notifyListeners();
      }
    }
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

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
