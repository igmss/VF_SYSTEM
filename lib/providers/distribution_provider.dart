import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/bank_account.dart';
import '../models/retailer.dart';
import '../models/collector.dart';
import '../models/financial_transaction.dart';
import 'auth_provider.dart';

part 'bank_account_operations.dart';
part 'retailer_collector_operations.dart';

class DistributionProvider extends ChangeNotifier with BankAccountOperationsMixin, RetailerCollectorOperationsMixin {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-east1');

  List<BankAccount> _bankAccounts = [];
  List<Retailer> _retailers = [];
  List<Collector> _collectors = [];
  List<FinancialTransaction> _ledger = [];
  Map<String, String> _userNames = {}; // UID -> Name
  double _usdtBalance = 0.0;     // USDT quantity in the exchange
  double _usdtLastPrice = 0.0;  // Last known EGP/USDT price (for EGP equivalent)

  bool _isLoading = false;
  bool _isListenersInitialized = false;
  bool _syncCompleted = false;

  // Per-action in-flight flags
  bool _isDistributing = false;
  bool _isCollecting = false;
  bool _isDepositing = false;
  bool _isCorrecting = false;
  bool _isCreditReturning = false;
  bool _isDeleting = false;
  bool _isInternalTransferring = false;

  bool get isDistributing    => _isDistributing;
  bool get isCollecting      => _isCollecting;
  bool get isDepositing      => _isDepositing;
  bool get isCreditReturning => _isCreditReturning;
  bool get isInternalTransferring => _isInternalTransferring;
  String? _error;

  StreamSubscription<DatabaseEvent>? _usdExchangeSub;
  StreamSubscription<DatabaseEvent>? _banksSub;
  StreamSubscription<DatabaseEvent>? _retailersSub;
  StreamSubscription<DatabaseEvent>? _collectorsSub;
  StreamSubscription<DatabaseEvent>? _ledgerSub;

  List<BankAccount> get bankAccounts => _bankAccounts;
  List<Retailer> get retailers => _retailers;
  List<Collector> get collectors => _collectors;
  List<FinancialTransaction> get ledger => _ledger;

  /// USDT quantity held in USD Exchange
  double get usdtBalance => _usdtBalance;

  /// Last known EGP price per USDT
  double get usdtLastPrice => _usdtLastPrice;

  /// EGP equivalent of the USDT balance
  double get totalUsdExchangeBalance => _usdtBalance * (_usdtLastPrice > 0 ? _usdtLastPrice : 1);

  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, String> get userNames => _userNames;

  // ——————————————————————————————————————————————————————————————————————————
  //  Aggregate Totals
  // ——————————————————————————————————————————————————————————————————————————

  double get totalBankBalance =>
      _bankAccounts.fold(0, (sum, b) => sum + b.balance);

  BankAccount? get defaultBuyBank {
    try {
      return _bankAccounts.firstWhere((a) => a.isDefaultForBuy);
    } catch (_) {
      return _bankAccounts.isNotEmpty ? _bankAccounts.first : null;
    }
  }

  double get totalRetailerDebt =>
      _retailers.fold(0, (sum, r) => sum + r.pendingDebt);

  double get totalCollectorCash =>
      _collectors.fold(0, (sum, c) => sum + c.cashOnHand);

  double get totalTransferFees =>
      _ledger.where((tx) => tx.type == FlowType.EXPENSE_VFCASH_FEE).fold(0.0, (sum, tx) => sum + tx.amount);

  double get totalVfDepositProfit => _ledger
      .where((tx) => tx.type == FlowType.VFCASH_RETAIL_PROFIT)
      .fold(0.0, (sum, tx) => sum + tx.amount);

  double get totalCreditReturnProfit => _ledger
      .where((tx) => tx.type == FlowType.CREDIT_RETURN_FEE)
      .fold(0.0, (sum, tx) => sum + tx.amount);


  // ——————————————————————————————————————————————————————————————————————————
  //  Lifecycle & Real-Time Listeners
  // ——————————————————————————————————————————————————————————————————————————

  Future<void> loadAll() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _initializeListeners();
      await Future.wait([
        _refreshOperationalData(),
        _refreshUsdExchangeData(),
      ]);
      if (!_syncCompleted) {
        await _syncCollectorsFromUsers();
        _syncCompleted = true;
      }
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadUserNames(AuthProvider auth) async {
    try {
      final users = await auth.getAllUsers();
      _userNames = {for (var u in users) u.uid: u.name};
      notifyListeners();
    } catch (_) {}
  }

  void _initializeListeners() {
    if (_isListenersInitialized) return;
    _isListenersInitialized = true;

    _usdExchangeSub?.cancel();
    _usdExchangeSub = _db.ref('usd_exchange').onValue.listen((event) {
      final snap = event.snapshot;
      if (snap.exists && snap.value != null && snap.value is Map) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _usdtBalance = _asDouble(data['usdtBalance'] ?? data['balance'] ?? data['usdt']);
        _usdtLastPrice = _asDouble(data['lastPrice'] ?? data['price'] ?? data['egpPrice']);
      } else {
        _usdtBalance = 0.0;
        _usdtLastPrice = 0.0;
      }
      notifyListeners();
    });

    _banksSub?.cancel();
    _banksSub = _db.ref('bank_accounts').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        _bankAccounts = [];
      } else {
        final map = snap.value as Map;
        _bankAccounts = map.values
            .whereType<Map>()
            .map((v) => BankAccount.fromMap(Map<String, dynamic>.from(v)))
            .toList();
        _bankAccounts.sort((a, b) {
          if (a.isDefaultForBuy == b.isDefaultForBuy) {
            return a.bankName.compareTo(b.bankName);
          }
          return a.isDefaultForBuy ? -1 : 1;
        });
      }
      notifyListeners();
    });

    _retailersSub?.cancel();
    _retailersSub = _db.ref('retailers').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        _retailers = [];
      } else {
        final map = snap.value as Map;
        _retailers = map.values
            .whereType<Map>()
            .map((v) => Retailer.fromMap(Map<String, dynamic>.from(v)))
            .where((r) => r.isActive)
            .toList();
        _retailers.sort((a, b) => a.name.compareTo(b.name));
      }
      notifyListeners();
    });

    _collectorsSub?.cancel();
    _collectorsSub = _db.ref('collectors').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        _collectors = [];
      } else {
        final map = snap.value as Map;
        _collectors = map.entries
            .where((entry) => entry.value is Map)
            .map((entry) {
              final data = Map<String, dynamic>.from(entry.value as Map);
              data['id'] = entry.key.toString();
              return Collector.fromMap(data);
            })
            .where((c) => c.isActive)
            .toList();
        _collectors.sort((a, b) => a.name.compareTo(b.name));
      }
      notifyListeners();
    });

    _ledgerSub?.cancel();
    _ledgerSub = _db.ref('financial_ledger').orderByChild('timestamp').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        _ledger = [];
      } else {
        final map = snap.value as Map;
        _ledger = map.values
            .whereType<Map>()
            .map((v) => FinancialTransaction.fromMap(Map<String, dynamic>.from(v)))
            .toList();
        _ledger.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      notifyListeners();
    });
  }

  Future<void> _refreshOperationalData() async {
    final results = await Future.wait([
      _db.ref('bank_accounts').get(),
      _db.ref('retailers').get(),
      _db.ref('collectors').get(),
      _db.ref('financial_ledger').get(),
    ]);

    final banksSnap = results[0];
    if (!banksSnap.exists || banksSnap.value == null || banksSnap.value is! Map) {
      _bankAccounts = [];
    } else {
      final map = banksSnap.value as Map;
      _bankAccounts = map.values
          .whereType<Map>()
          .map((v) => BankAccount.fromMap(Map<String, dynamic>.from(v)))
          .toList();
      _bankAccounts.sort((a, b) {
        if (a.isDefaultForBuy == b.isDefaultForBuy) {
          return a.bankName.compareTo(b.bankName);
        }
        return a.isDefaultForBuy ? -1 : 1;
      });
    }

    final retailersSnap = results[1];
    if (!retailersSnap.exists || retailersSnap.value == null || retailersSnap.value is! Map) {
      _retailers = [];
    } else {
      final map = retailersSnap.value as Map;
      _retailers = map.values
          .whereType<Map>()
          .map((v) => Retailer.fromMap(Map<String, dynamic>.from(v)))
          .where((r) => r.isActive)
          .toList();
      _retailers.sort((a, b) => a.name.compareTo(b.name));
    }

    final collectorsSnap = results[2];
    if (!collectorsSnap.exists || collectorsSnap.value == null || collectorsSnap.value is! Map) {
      _collectors = [];
    } else {
      final map = collectorsSnap.value as Map;
      _collectors = map.entries
          .where((entry) => entry.value is Map)
          .map((entry) {
            final data = Map<String, dynamic>.from(entry.value as Map);
            data['id'] = entry.key.toString();
            return Collector.fromMap(data);
          })
          .where((c) => c.isActive)
          .toList();
      _collectors.sort((a, b) => a.name.compareTo(b.name));
    }

    final ledgerSnap = results[3];
    if (!ledgerSnap.exists || ledgerSnap.value == null || ledgerSnap.value is! Map) {
      _ledger = [];
    } else {
      final map = ledgerSnap.value as Map;
      _ledger = map.values
          .whereType<Map>()
          .map((v) => FinancialTransaction.fromMap(Map<String, dynamic>.from(v)))
          .toList();
      _ledger.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    notifyListeners();
  }

  Future<void> _refreshUsdExchangeData() async {
    try {
      final snap = await _db.ref('usd_exchange').get();
      if (snap.exists && snap.value != null && snap.value is Map) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _usdtBalance = _asDouble(data['usdtBalance'] ?? data['balance'] ?? data['usdt']);
        _usdtLastPrice = _asDouble(data['lastPrice'] ?? data['price'] ?? data['egpPrice']);
      } else {
        _usdtBalance = 0.0;
        _usdtLastPrice = 0.0;
      }
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _usdExchangeSub?.cancel();
    _banksSub?.cancel();
    _retailersSub?.cancel();
    _collectorsSub?.cancel();
    _ledgerSub?.cancel();
    super.dispose();
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Future<void> setUsdExchangeBalance(double usdtAmount) async {
    _usdtBalance = usdtAmount;
    await _db.ref('usd_exchange/usdtBalance').set(usdtAmount);
    await _db.ref('usd_exchange/balance').set(usdtAmount);
    await _db.ref('usd_exchange/lastUpdatedAt').set(DateTime.now().toIso8601String());
    notifyListeners();
  }

  Future<void> _addUsdtBalance(double usdtQty, double price) async {
    _usdtBalance += usdtQty;
    if (price > 0) _usdtLastPrice = price;
    await _db.ref('usd_exchange').update({
      'usdtBalance': _usdtBalance,
      'balance': _usdtBalance,
      if (price > 0) 'lastPrice': price,
      'lastUpdatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _subtractUsdtBalance(double usdtQty, double price) async {
    _usdtBalance = (_usdtBalance - usdtQty).clamp(0.0, double.infinity);
    if (price > 0) _usdtLastPrice = price;
    await _db.ref('usd_exchange').update({
      'usdtBalance': _usdtBalance,
      'balance': _usdtBalance,
      if (price > 0) 'lastPrice': price,
      'lastUpdatedAt': DateTime.now().toIso8601String(),
    });
  }

  // ——————————————————————————————————————————————————————————————————————————
  //  Load Stubs (Used by loadAll)
  // ——————————————————————————————————————————————————————————————————————————

  Future<void> _loadBankAccounts() async {}
  Future<void> _loadRetailers() async {}
  Future<void> _loadCollectors() async {}
  Future<void> _loadLedger() async {}

  // ——————————————————————————————————————————————————————————————————————————
  //  Collector-role helpers
  // ——————————————————————————————————————————————————————————————————————————

  List<Retailer> getMyRetailers(String collectorUid) =>
      _retailers.where((r) => r.assignedCollectorId == collectorUid).toList();

  Collector? getMyCollector(String uid) {
    try {
      return _collectors.firstWhere((c) => c.uid == uid);
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncCollectorsFromUsers() async {
    try {
      final snap = await _db.ref('users').get();
      if (!snap.exists || snap.value == null || snap.value is! Map) return;

      final collectorsSnap = await _db.ref('collectors').get();
      final existingCollectorUids = <String>{};
      if (collectorsSnap.exists && collectorsSnap.value is Map) {
        existingCollectorUids.addAll((collectorsSnap.value as Map).keys.cast<String>());
      }

      final usersMap = snap.value as Map;
      bool added = false;

      for (final entry in usersMap.entries) {
        final uid = entry.key.toString();
        final val = entry.value;
        if (val is! Map) continue;
        final data = Map<String, dynamic>.from(val);
        if (data['role'] != 'COLLECTOR') continue;

        if (!existingCollectorUids.contains(uid)) {
          final collectorData = {
            'id': uid,
            'name': data['name']?.toString() ?? '',
            'phone': '',
            'email': data['email']?.toString() ?? '',
            'uid': uid,
            'cashOnHand': 0.0,
            'cashLimit': 50000.0,
            'totalCollected': 0.0,
            'totalDeposited': 0.0,
            'isActive': true,
            'createdAt': data['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
            'lastUpdatedAt': DateTime.now().toIso8601String(),
          };
          await _db.ref('collectors/$uid').set(collectorData);
          _collectors.add(Collector.fromMap(collectorData));
          added = true;
        }
      }

      if (added) {
        _collectors.sort((a, b) => a.name.compareTo(b.name));
      }
    } catch (e) {
      debugPrint('Error syncing collectors from users: $e');
    }
  }

  /// Admin: assigns (or unassigns) a retailer to a collector.
  Future<void> assignRetailerToCollector(
      String retailerId, String? collectorId) async {
    await _db
        .ref('retailers/$retailerId/assignedCollectorId')
        .set(collectorId); // null = unassign
    await _loadRetailers();
    notifyListeners();
  }

  /// Ensures a Collector record exists for the given UID (idempotent).
  Future<void> ensureCollectorRecord({
    required String uid,
    required String name,
    required String email,
  }) async {
    if (_collectors.any((c) => c.uid == uid)) return;
    final collectorData = {
      'id': uid,
      'name': name,
      'phone': '',
      'email': email,
      'uid': uid,
      'cashOnHand': 0.0,
      'cashLimit': 50000.0,
      'totalCollected': 0.0,
      'totalDeposited': 0.0,
      'isActive': true,
      'createdAt': DateTime.now().toIso8601String(),
      'lastUpdatedAt': DateTime.now().toIso8601String(),
    };
    await _db.ref('collectors/$uid').set(collectorData);
    _collectors.add(Collector.fromMap(collectorData));
    _collectors.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }
}
