import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';

import '../models/bank_account.dart';
import '../models/retailer.dart';
import '../models/collector.dart';
import '../models/financial_transaction.dart';

class DistributionProvider extends ChangeNotifier {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  List<BankAccount> _bankAccounts = [];
  List<Retailer> _retailers = [];
  List<Collector> _collectors = [];
  List<FinancialTransaction> _ledger = [];
  double _usdtBalance = 0.0;     // USDT quantity in the exchange
  double _usdtLastPrice = 0.0;  // Last known EGP/USDT price (for EGP equivalent)

  bool _isLoading = false;
  bool _isListenersInitialized = false;
  bool _syncCompleted = false;

  // Per-action in-flight flags (replaces the single shared _isProcessingAction
  // that was silently dropping concurrent calls).
  bool _isDistributing = false;
  bool _isCollecting = false;
  bool _isDepositing = false;
  bool _isCorrecting = false;
  bool _isCreditReturning = false;
  bool _isDeleting = false;

  bool get isDistributing    => _isDistributing;
  bool get isCollecting      => _isCollecting;
  bool get isDepositing      => _isDepositing;
  bool get isCreditReturning => _isCreditReturning;
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

  /// EGP equivalent of the USDT balance (used for total capital in EGP)
  double get totalUsdExchangeBalance => _usdtBalance * (_usdtLastPrice > 0 ? _usdtLastPrice : 1);

  bool get isLoading => _isLoading;
  String? get error => _error;

  // ─── Aggregate totals ──────────────────────────────────────────────────────

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

  // ─── Real-Time Data Listeners ──────────────────────────────────────────────

  Future<void> loadAll() async {
    _isLoading = true;
    _error = null;
    // Notify once before we start listening so the UI can show a spinner if needed
    notifyListeners();

    try {
      _initializeListeners();
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

  void _initializeListeners() {
    if (_isListenersInitialized) return;
    _isListenersInitialized = true;

    _usdExchangeSub?.cancel();
    _usdExchangeSub = _db.ref('usd_exchange').onValue.listen((event) {
      final snap = event.snapshot;
      if (snap.exists && snap.value != null && snap.value is Map) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _usdtBalance = _asDouble(data['usdtBalance']);
        _usdtLastPrice = _asDouble(data['lastPrice']);
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
        _bankAccounts = map.values.where((v) => v is Map).map((v) {
          return BankAccount.fromMap(Map<String, dynamic>.from(v as Map));
        }).toList();
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
            .where((v) => v is Map)
            .map((v) => Retailer.fromMap(Map<String, dynamic>.from(v as Map)))
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
        _collectors = map.values
            .where((v) => v is Map)
            .map((v) => Collector.fromMap(Map<String, dynamic>.from(v as Map)))
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
            .where((v) => v is Map)
            .map((v) => FinancialTransaction.fromMap(Map<String, dynamic>.from(v as Map)))
            .toList();
        _ledger.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // newest first
      }
      notifyListeners();
    });
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

  // We keep `loadAll()` calling `_syncCollectorsFromUsers()` to ensure sync on startup,
  // but we replaced the body of `_loadBankAccounts`, `_loadRetailers`, etc. 
  // since they are now handled entirely by the robust `.onValue` listeners defined above!

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  /// Manually set USDT balance (admin override).
  Future<void> setUsdExchangeBalance(double usdtAmount) async {
    _usdtBalance = usdtAmount;
    await _db.ref('usd_exchange/usdtBalance').set(usdtAmount);
    await _db.ref('usd_exchange/lastUpdatedAt').set(DateTime.now().toIso8601String());
    notifyListeners();
  }

  /// Add USDT to the exchange balance (on BUY USDT order).
  Future<void> _addUsdtBalance(double usdtQty, double price) async {
    _usdtBalance += usdtQty;
    if (price > 0) _usdtLastPrice = price;
    await _db.ref('usd_exchange').update({
      'usdtBalance': _usdtBalance,
      if (price > 0) 'lastPrice': price,
      'lastUpdatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Subtract USDT from the exchange balance (on SELL USDT order).
  Future<void> _subtractUsdtBalance(double usdtQty, double price) async {
    _usdtBalance = (_usdtBalance - usdtQty).clamp(0.0, double.infinity);
    if (price > 0) _usdtLastPrice = price;
    await _db.ref('usd_exchange').update({
      'usdtBalance': _usdtBalance,
      if (price > 0) 'lastPrice': price,
      'lastUpdatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _loadBankAccounts() async {}
  Future<void> _loadRetailers() async {}
  Future<void> _loadCollectors() async {}
  Future<void> _loadLedger() async {}
  Future<void> _loadUsdExchangeBalance() async {}


  /// Reads all users with role == 'COLLECTOR' from the users node.
  /// For each one that has no matching collectors/ record (by uid),
  /// auto-creates the record so they appear in the Collectors screen.
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

        // Check if a collector record with this uid actually exists in Firebase
        if (!existingCollectorUids.contains(uid)) {
          // Create the missing collector record in the database
          debugPrint('Auto-creating collector record for user $uid (${data['name']})');
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

  // Ledger data stream previously here is now in `_initializeListeners()`
  // ─── Collector-role helpers ─────────────────────────────────────────────────

  /// Returns retailers assigned to this collector's UID (for COLLECTOR role).
  List<Retailer> getMyRetailers(String collectorUid) =>
      _retailers.where((r) => r.assignedCollectorId == collectorUid).toList();

  /// Returns the Collector record linked to this Firebase Auth UID.
  Collector? getMyCollector(String uid) {
    try {
      return _collectors.firstWhere((c) => c.uid == uid);
    } catch (_) {
      return null;
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
  /// Called when admin manually picks a COLLECTOR user from the picker.
  Future<void> ensureCollectorRecord({
    required String uid,
    required String name,
    required String email,
  }) async {
    // Check if already exists
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

  // ─── Bank Account CRUD ─────────────────────────────────────────────────────

  Future<void> addBankAccount(BankAccount account, {String createdByUid = 'system'}) async {
    // If no banks exist, make the first one the default automatically
    if (_bankAccounts.isEmpty) {
      final accMap = account.toMap();
      accMap['isDefaultForBuy'] = true;
      account = BankAccount.fromMap(accMap);
    }

    await _db.ref('bank_accounts/${account.id}').set(account.toMap());

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
      await _db.ref('financial_ledger/${openingTx.id}').set(openingTx.toMap());
    }

    await _loadBankAccounts();
    notifyListeners();
  }

  Future<void> deleteBankAccount(String id) async {
    // ── Stamp ledger entries that reference this bank ─────────────────────
    // Before removing the bank record, mark all related ledger entries so the
    // UI can show "[Deleted Account]" instead of a dangling label.
    try {
      final ledgerSnap = await _db.ref('financial_ledger').get();
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
          await _db.ref().update(updates);
          debugPrint('Marked ${updates.length} ledger fields as [Deleted Account] for bank $id');
        }
      }
    } catch (e) {
      debugPrint('Error stamping deleted bank ledger entries: $e');
    }
    // ── Remove the bank ───────────────────────────────────────────────────
    await _db.ref('bank_accounts/$id').remove();
    _bankAccounts.removeWhere((b) => b.id == id);
    // If we deleted the default bank, make the first remaining one the default
    if (_bankAccounts.isNotEmpty && !_bankAccounts.any((b) => b.isDefaultForBuy)) {
      await setDefaultBuyBank(_bankAccounts.first.id);
    }
    await _loadLedger(); // reload so in-memory ledger reflects the new labels
    notifyListeners();
  }

  /// Set Bank Account as Default for Buying USDT
  Future<void> setDefaultBuyBank(String bankId) async {
    final updates = <String, dynamic>{};
    for (final bank in _bankAccounts) {
      if (bank.isDefaultForBuy && bank.id != bankId) {
        updates['bank_accounts/${bank.id}/isDefaultForBuy'] = false;
      } else if (!bank.isDefaultForBuy && bank.id == bankId) {
        updates['bank_accounts/${bank.id}/isDefaultForBuy'] = true;
      }
    }
    if (updates.isNotEmpty) {
      await _db.ref().update(updates);
      await _loadBankAccounts();
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
    final bank = defaultBuyBank;
    if (bank == null) {
      debugPrint('Buy USDT: No default bank account — recording USD Exchange increase only.');
    }

    // Safety check: is Duplicate? Wrap in try/catch — if bybitOrderId index is not yet
    // deployed on Firebase, the query throws, but we must NOT block processing.
    try {
      final ledgerQuery = await _db.ref('financial_ledger')
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
        // Use an atomic transaction to ensure safe concurrent subtractions
        await _db.ref('bank_accounts/${bank.id}/balance').runTransaction((Object? currentBalance) {
          if (currentBalance == null) {
            return Transaction.success(0.0 - egpAmount);
          }
          final balance = double.tryParse(currentBalance.toString()) ?? 0.0;
          return Transaction.success(balance - egpAmount);
        });
        await _db.ref('bank_accounts/${bank.id}/lastUpdatedAt').set(DateTime.now().toIso8601String());
      }

      // 2. Add to USD Exchange balance (USDT quantity + last price)
      await _addUsdtBalance(usdtQuantity, usdtPrice);

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
      await _db.ref('financial_ledger/${tx.id}').set(tx.toMap());

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
    final bank = _bankAccounts.firstWhere((b) => b.id == bankAccountId);
    final tx = FinancialTransaction(
      type: FlowType.FUND_BANK,
      amount: amount,
      toId: bankAccountId,
      toLabel: bank.bankName,
      createdByUid: createdByUid,
      notes: notes,
    );
    final updatedBalance = bank.balance + amount;
    await Future.wait([
      _db.ref('financial_ledger/${tx.id}').set(tx.toMap()),
      _db.ref('bank_accounts/$bankAccountId/balance').set(updatedBalance),
      _db.ref('bank_accounts/$bankAccountId/lastUpdatedAt')
          .set(DateTime.now().toIso8601String()),
    ]);
    await loadAll();
  }

  /// Deduct from a bank account balance (for corrections / missed deductions).
  /// Records a BANK_DEDUCTION ledger entry and decreases the bank balance.
  Future<void> deductBankBalance({
    required String bankAccountId,
    required double amount,
    required String createdByUid,
    String? notes,
  }) async {
    final bank = _bankAccounts.firstWhere((b) => b.id == bankAccountId);
    final tx = FinancialTransaction(
      type: FlowType.BANK_DEDUCTION,
      amount: amount,
      fromId: bankAccountId,
      fromLabel: bank.bankName,
      createdByUid: createdByUid,
      notes: notes,
    );
    final updatedBalance = bank.balance - amount;
    await Future.wait([
      _db.ref('financial_ledger/${tx.id}').set(tx.toMap()),
      _db.ref('bank_accounts/$bankAccountId/balance').set(updatedBalance),
      _db.ref('bank_accounts/$bankAccountId/lastUpdatedAt')
          .set(DateTime.now().toIso8601String()),
    ]);
    await loadAll();
  }

  // ─── One-time fix: correct wrong BALANCE_CORRECTION FUND_BANK entry ────────

  /// Finds any FUND_BANK ledger entry whose notes start with "BALANCE_CORRECTION"
  /// and converts it to a proper BANK_DEDUCTION, correcting the bank balance.
  /// The wrong entry added +amount to the bank when it should have deducted -amount,
  /// so the total correction = -2 * amount (undo the wrong credit + apply the debit).
  Future<Map<String, dynamic>> fixWrongCorrectionEntry({required String createdByUid}) async {
    final wrongEntries = _ledger.where((tx) =>
        tx.type == FlowType.FUND_BANK &&
        (tx.notes?.startsWith('BALANCE_CORRECTION') ?? false)).toList();

    if (wrongEntries.isEmpty) {
      return {'fixed': 0, 'message': 'No wrong BALANCE_CORRECTION entries found.'};
    }

    int fixed = 0;
    for (final wrongTx in wrongEntries) {
      final bankId = wrongTx.toId; // FUND_BANK goes TO a bank
      if (bankId == null) continue;

      final bIndex = _bankAccounts.indexWhere((b) => b.id == bankId);
      if (bIndex == -1) continue;

      final bank = _bankAccounts[bIndex];
      // The wrong entry added +amount. Correct balance = current - amount (undo credit) - amount (apply debit) = current - 2*amount
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
        // Remove the wrong FUND_BANK entry
        _db.ref('financial_ledger/${wrongTx.id}').remove(),
        // Add the correct BANK_DEDUCTION entry
        _db.ref('financial_ledger/${fixTx.id}').set(fixTx.toMap()),
        // Fix the bank balance
        _db.ref('bank_accounts/$bankId/balance').set(correctedBalance),
        _db.ref('bank_accounts/$bankId/lastUpdatedAt').set(DateTime.now().toIso8601String()),
      ]);
      fixed++;
    }

    return {'fixed': fixed, 'message': 'Fixed $fixed wrong BALANCE_CORRECTION entries.'};
  }

  // ─── Retailer CRUD ─────────────────────────────────────────────────────────

  /// ONE-TIME MIGRATION: Round up all retailers' totalAssigned to nearest integer.
  Future<int> roundAllRetailerAssignments() async {
    int fixed = 0;
    for (final retailer in _retailers) {
      final rounded = retailer.totalAssigned.ceilToDouble();
      if (rounded != retailer.totalAssigned) {
        await _db.ref('retailers/${retailer.id}/totalAssigned').set(rounded);
        fixed++;
      }
    }
    await _loadRetailers();
    notifyListeners();
    return fixed;
  }

  Future<void> addRetailer(Retailer retailer) async {
    await _db.ref('retailers/${retailer.id}').set(retailer.toMap());
    await _loadRetailers();
    notifyListeners();
  }

  Future<void> updateRetailer(Retailer retailer) async {
    await _db.ref('retailers/${retailer.id}').update(retailer.toMap());
    await _loadRetailers();
    notifyListeners();
  }

  Future<void> deactivateRetailer(String id) async {
    await _db.ref('retailers/$id/isActive').set(false);
    _retailers.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  /// Transfer Vodafone Cash to a Retailer.
  /// This records a DISTRIBUTE_VFCASH ledger entry and increases the Retailer's debt.
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
    if (_isDistributing) return;
    _isDistributing = true;
    notifyListeners();
    try {
      final retailer = _retailers.firstWhere((r) => r.id == retailerId);

      // Calculate the actual debt increase based on the discount rate per 1000 EGP
      final double discountAmount = (amount / 1000.0) * retailer.discountPer1000;

      // If external wallet, the retailer pays the transfer fees
      final double feeToCharge = chargeFeesToRetailer ? fees : 0.0;

      // Round UP to nearest integer so collectors always deal with whole amounts
      double actualDebtIncrease = (amount + discountAmount + feeToCharge).ceilToDouble();

      double creditUsed = 0.0;
      if (applyCredit && retailer.credit > 0) {
        creditUsed = retailer.credit > actualDebtIncrease ? actualDebtIncrease : retailer.credit;
        actualDebtIncrease -= creditUsed;
      }

      String feeNotes = chargeFeesToRetailer && fees > 0 ? ', +$fees Fee' : '';
      String creditNotes = creditUsed > 0 ? ', -$creditUsed Credit Used' : '';
      final String appliedNotes = notes != null && notes.isNotEmpty
          ? '$notes (Rate: ${retailer.discountPer1000}/1K$feeNotes$creditNotes, Debt +$actualDebtIncrease EGP)'
          : 'Rate: ${retailer.discountPer1000}/1K$feeNotes$creditNotes, Debt +$actualDebtIncrease EGP';

      final tx = FinancialTransaction(
        type: FlowType.DISTRIBUTE_VFCASH,
        amount: amount,
        fromId: fromVfNumberId,
        fromLabel: fromVfPhone,
        toId: retailerId,
        toLabel: retailer.name,
        createdByUid: createdByUid,
        notes: appliedNotes,
      );

      // The VF number ALWAYS loses (amount + fees) — that is the physical transfer cost.
      final cashTxId = const Uuid().v4();
      final double totalDeduction = amount + fees;
      final cashTxMap = {
        'id': cashTxId,
        'phoneNumber': fromVfPhone,
        'amount': totalDeduction,
        'currency': 'EGP',
        'timestamp': DateTime.now().toIso8601String(),
        'bybitOrderId': 'DIST-${tx.id.substring(0, 8)}',
        'status': 'completed',
        'paymentMethod': 'Vodafone Distribution',
        'side': 0, // Outgoing
        'chatHistory': fees > 0
            ? 'Automated Distribution to ${retailer.name} (Includes $fees EGP transfer fees${chargeFeesToRetailer ? " – charged to retailer" : ""})'
            : 'Automated Distribution to ${retailer.name}',
      };

      // Build atomic multi-path update
      final now = DateTime.now().toIso8601String();
      final updates = <String, dynamic>{
        'financial_ledger/${tx.id}': tx.toMap(),
        'transactions/$cashTxId': cashTxMap,
        'retailers/$retailerId/totalAssigned': retailer.totalAssigned + actualDebtIncrease,
        'retailers/$retailerId/lastUpdatedAt': now,
      };

      if (creditUsed > 0) {
        updates['retailers/$retailerId/credit'] = retailer.credit - creditUsed;
      }

      if (fees > 0) {
        final feeTx = FinancialTransaction(
          type: FlowType.EXPENSE_VFCASH_FEE,
          amount: fees,
          fromId: fromVfNumberId,
          fromLabel: fromVfPhone,
          createdByUid: createdByUid,
          notes: chargeFeesToRetailer
              ? 'Vodafone Transfer Fee for assigning $amount EGP to ${retailer.name} (charged to retailer debt)'
              : 'Vodafone Transfer Fee for assigning $amount EGP to ${retailer.name}',
        );
        updates['financial_ledger/${feeTx.id}'] = feeTx.toMap();
      }

      await _db.ref().update(updates);
    } finally {
      _isDistributing = false;
      notifyListeners();
    }
  }

  // ─── Collector CRUD ────────────────────────────────────────────────────────

  Future<void> addCollector(Collector collector) async {
    await _db.ref('collectors/${collector.id}').set(collector.toMap());
    await _loadCollectors();
    notifyListeners();
  }

  Future<void> updateCollector(Collector collector) async {
    await _db.ref('collectors/${collector.id}').update(collector.toMap());
    await _loadCollectors();
    notifyListeners();
  }

  Future<void> deactivateCollector(String id) async {
    await _db.ref('collectors/$id/isActive').set(false);
    _collectors.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  /// Collector collects cash from a Retailer.
  Future<void> collectFromRetailer({
    required String collectorId,
    required String retailerId,
    required double amount,
    required String createdByUid,
    String? notes,
  }) async {
    if (_isCollecting) return;
    _isCollecting = true;
    notifyListeners();
    try {
      final collector = _collectors.firstWhere((c) => c.id == collectorId);
      final retailer = _retailers.firstWhere((r) => r.id == retailerId);

      // Handle excess credit
      double addedToCollected = amount;
      double addedToCredit = 0.0;

      if (amount > retailer.pendingDebt) {
        // Retailer pays more than what they owe
        addedToCollected = retailer.pendingDebt > 0 ? retailer.pendingDebt : 0.0;
        addedToCredit = amount - addedToCollected;
      }

      String? appliedNotes = notes;
      if (addedToCredit > 0) {
        final creditNote = '(+${addedToCredit.toStringAsFixed(0)} EGP added to Credit)';
        appliedNotes = notes != null && notes.isNotEmpty ? '$notes $creditNote' : creditNote;
      }

      final tx = FinancialTransaction(
        type: FlowType.COLLECT_CASH,
        amount: amount,
        fromId: retailerId,
        fromLabel: retailer.name,
        toId: collectorId,
        toLabel: collector.name,
        createdByUid: createdByUid,
        notes: appliedNotes,
      );

      final now = DateTime.now().toIso8601String();
      final updates = <String, dynamic>{
        'financial_ledger/${tx.id}': tx.toMap(),
        'retailers/$retailerId/lastUpdatedAt': now,
        'collectors/$collectorId/cashOnHand': collector.cashOnHand + amount,
        'collectors/$collectorId/totalCollected': collector.totalCollected + amount,
        'collectors/$collectorId/lastUpdatedAt': now,
      };

      if (addedToCollected > 0) {
        updates['retailers/$retailerId/totalCollected'] =
            retailer.totalCollected + addedToCollected;
      }
      if (addedToCredit > 0) {
        updates['retailers/$retailerId/credit'] =
            retailer.credit + addedToCredit;
      }

      // Single atomic multi-path update — Firebase applies all fields at once,
      // triggers each .onValue listener once with the final state.
      await _db.ref().update(updates);
    } finally {
      _isCollecting = false;
      notifyListeners();
    }
  }

  /// Collector deposits cash into a Bank Account.
  Future<void> depositToBank({
    required String collectorId,
    required String bankAccountId,
    required double amount,
    required String createdByUid,
    String? notes,
  }) async {
    if (_isDepositing) return;
    _isDepositing = true;
    notifyListeners();
    try {
      final collector = _collectors.firstWhere((c) => c.id == collectorId);
      final bank = _bankAccounts.firstWhere((b) => b.id == bankAccountId);
    final tx = FinancialTransaction(
      type: FlowType.DEPOSIT_TO_BANK,
      amount: amount,
      fromId: collectorId,
      fromLabel: collector.name,
      toId: bankAccountId,
      toLabel: bank.bankName,
      createdByUid: createdByUid,
      notes: notes,
    );
    final now = DateTime.now().toIso8601String();
    await _db.ref().update({
      'financial_ledger/${tx.id}': tx.toMap(),
      'collectors/$collectorId/cashOnHand': collector.cashOnHand - amount,
      'collectors/$collectorId/totalDeposited': collector.totalDeposited + amount,
      'collectors/$collectorId/lastUpdatedAt': now,
      'bank_accounts/$bankAccountId/balance': bank.balance + amount,
      'bank_accounts/$bankAccountId/lastUpdatedAt': now,
    });
    } finally {
      _isDepositing = false;
      notifyListeners();
    }
  }

  /// Admin: Correct a mistaken "Collect Cash" or "Deposit to Bank" transaction.
  /// This creates an adjustment entry and corrects the affected balances.
  Future<void> correctTransaction({
    required FinancialTransaction originalTx,
    required double correctAmount,
    required String adminUid,
    String? reason,
  }) async {
    if (_isCorrecting) return;
    _isCorrecting = true;
    try {
      final double diff = correctAmount - originalTx.amount;
      if (diff == 0) return;

      final now = DateTime.now();
      final adjustmentTx = FinancialTransaction(
        type: FlowType.ADMIN_ADJUSTMENT,
        amount: diff.abs(),
        fromId: originalTx.fromId,
        fromLabel: originalTx.fromLabel,
        toId: originalTx.toId,
        toLabel: originalTx.toLabel,
        bybitOrderId: originalTx.bybitOrderId,
        notes: 'CORRECTION for ${originalTx.id}: ${reason ?? "Amount adjusted from ${originalTx.amount} to $correctAmount"}',
        createdByUid: adminUid,
        timestamp: now,
      );

      final futures = <Future<void>>[];
      // 0. Update the ORIGINAL transaction amount in the ledger to reflect truth
      futures.add(_db.ref('financial_ledger/${originalTx.id}/amount').set(correctAmount));
      futures.add(_db.ref('financial_ledger/${originalTx.id}/notes')
          .set('${originalTx.notes ?? ""} (Corrected from ${originalTx.amount} by Admin)'.trim()));

      // 1. Create an ADJUSTMENT entry for the audit trail
      futures.add(_db.ref('financial_ledger/${adjustmentTx.id}').set(adjustmentTx.toMap()));

      if (originalTx.type == FlowType.COLLECT_CASH) {
        final retailerId = originalTx.fromId;
        final collectorId = originalTx.toId;
        debugPrint('Correcting COLLECT_CASH for Retailer: $retailerId, Collector: $collectorId, Diff: $diff');

        if (retailerId != null) {
          final rIndex = _retailers.indexWhere((r) => r.id == retailerId);
          if (rIndex != -1) {
            final r = _retailers[rIndex];
            final newVal = r.totalCollected + diff;
            debugPrint('Retailer ${r.name}: Current collected=${r.totalCollected}, Diff=$diff, New Total=$newVal');
            futures.add(_db.ref('retailers/$retailerId/totalCollected').set(newVal));
            futures.add(_db.ref('retailers/$retailerId/lastUpdatedAt').set(now.toIso8601String()));
          }
        }
        if (collectorId != null) {
          final cIndex = _collectors.indexWhere((c) => c.uid == collectorId || c.id == collectorId);
          if (cIndex != -1) {
            final c = _collectors[cIndex];
            futures.add(_db.ref('collectors/${c.id}/cashOnHand').set(c.cashOnHand + diff));
            futures.add(_db.ref('collectors/${c.id}/totalCollected').set(c.totalCollected + diff));
            futures.add(_db.ref('collectors/${c.id}/lastUpdatedAt').set(now.toIso8601String()));
          }
        }
      } else if (originalTx.type == FlowType.DEPOSIT_TO_BANK) {
        final collectorId = originalTx.fromId;
        final bankId = originalTx.toId;
        debugPrint('Correcting DEPOSIT_TO_BANK for Collector: $collectorId, Bank: $bankId, Diff: $diff');

        if (bankId != null) {
          final bIndex = _bankAccounts.indexWhere((b) => b.id == bankId);
          if (bIndex != -1) {
            final b = _bankAccounts[bIndex];
            futures.add(_db.ref('bank_accounts/$bankId/balance').set(b.balance + diff));
            futures.add(_db.ref('bank_accounts/$bankId/lastUpdatedAt').set(now.toIso8601String()));
          }
        }
        if (collectorId != null) {
          final cIndex = _collectors.indexWhere((c) => c.uid == collectorId || c.id == collectorId);
          if (cIndex != -1) {
            final c = _collectors[cIndex];
            futures.add(_db.ref('collectors/${c.id}/cashOnHand').set(c.cashOnHand - diff));
            futures.add(_db.ref('collectors/${c.id}/totalDeposited').set(c.totalDeposited + diff));
            futures.add(_db.ref('collectors/${c.id}/lastUpdatedAt').set(now.toIso8601String()));
          }
        }
      } else if (originalTx.type == FlowType.CREDIT_RETURN) {
        final retailerId = originalTx.fromId;
        debugPrint('Correcting CREDIT_RETURN for Retailer: $retailerId, Diff: $diff');
        if (retailerId != null) {
          final rIndex = _retailers.indexWhere((r) => r.id == retailerId);
          if (rIndex != -1) {
            final r = _retailers[rIndex];
            futures.add(_db.ref('retailers/$retailerId/totalCollected').set(r.totalCollected + diff));
            futures.add(_db.ref('retailers/$retailerId/lastUpdatedAt').set(now.toIso8601String()));
          }
        }
      }

      await Future.wait(futures);
    } catch (e) {
      debugPrint('Correction error: $e');
      rethrow;
    } finally {
      _isCorrecting = false;
    }
  }

  /// Record a Bybit Buy USDT order (synced from Bybit). 
  /// Deducts fiat from the matched bank account.
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
    // 1. Strict deduplication check
    try {
      final ledgerQuery = await _db.ref('financial_ledger')
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
      return; // Do NOT proceed and create a duplicate if the check fails
    }

    final tx = FinancialTransaction(
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
    );

    // If we found a matching bank account, deduct balance ATOMICALLY.
    // Using runTransaction() prevents race conditions where concurrent syncs
    // read a stale in-memory balance and produce an incorrect result.
    if (matchedBankAccountId != null) {
      await _db.ref('bank_accounts/$matchedBankAccountId/balance').runTransaction((Object? data) {
        final current = (data as num?)?.toDouble() ?? 0.0;
        return Transaction.success(current - egpAmount);
      });
    }
    // Add to USD Exchange balance (USDT quantity)
    await _addUsdtBalance(usdtQuantity, usdtPrice);
    await _db.ref('financial_ledger/${tx.id}').set(tx.toMap());

    // ── Price snapshot for Exchange Rate chart (read-only append, no logic impact) ──
    if (usdtPrice > 0) {
      await _db.ref('price_history/${tx.id}').set({
        'price': usdtPrice,
        'side': 'buy',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// ONE-TIME: Manually correct a bank account balance by writing a correction
  /// ledger entry and updating the stored balance.
  Future<void> correctBankBalance({
    required String bankAccountId,
    required double newBalance,
    required String createdByUid,
    String? notes,
  }) async {
    final bank = _bankAccounts.firstWhere((b) => b.id == bankAccountId);
    final currentBal = bank.balance;
    final diff = newBalance - currentBal;

    final correctionTx = FinancialTransaction(
      type: FlowType.FUND_BANK,
      amount: diff.abs(),
      toId: diff >= 0 ? bankAccountId : null,
      fromId: diff < 0 ? bankAccountId : null,
      toLabel: diff >= 0 ? bank.bankName : 'Balance Correction',
      fromLabel: diff < 0 ? bank.bankName : 'Balance Correction',
      createdByUid: createdByUid,
      notes: 'BALANCE_CORRECTION: ${notes ?? "Manual Adjustment"}',
    );
    await _db.ref('bank_accounts/$bankAccountId/balance').set(newBalance);
    await _db.ref('financial_ledger/${correctionTx.id}').set(correctionTx.toMap());
  }

  /// Record a Bybit Sell USDT order (synced from Bybit).
  /// Adds EGP to the matched VF Cash number (tracked in app_provider).
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
    // Safety check: is Duplicate? Wrap in try/catch — if bybitOrderId index is not yet
    try {
      final ledgerQuery = await _db.ref('financial_ledger')
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
      return; // Do NOT proceed and create a duplicate if the check fails
    }

    try {
      final tx = FinancialTransaction(
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
      await _subtractUsdtBalance(usdtQuantity, usdtPrice);
      await _db.ref('financial_ledger/${tx.id}').set(tx.toMap());

      // ── Price snapshot for Exchange Rate chart (read-only append, no logic impact) ──
      if (usdtPrice > 0) {
        await _db.ref('price_history/${tx.id}').set({
          'price': usdtPrice,
          'side': 'sell',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (e) {
      debugPrint('Process Sell Order error: $e');
    }
  }

  /// Retailer pays debt via VF Cash.
  /// Deducts from retailer debt, increases VF number balance, and tracks fees.
  Future<void> creditReturn({
    required String retailerId,
    required String vfNumberId,
    required String vfPhone,
    required double amount, // base amount (debt reduction)
    required double fees,   // isolated fees
    required String createdByUid,
    String? notes,
  }) async {
    if (_isCreditReturning) return;
    _isCreditReturning = true;
    notifyListeners();
    try {
      final retailer = _retailers.firstWhere((r) => r.id == retailerId);
      final totalReceived = amount + fees;

      final now = DateTime.now();

      // 1. Transaction for the base amount (Debt Settlement)
      final tx = FinancialTransaction(
        type: FlowType.CREDIT_RETURN,
        amount: amount,
        fromId: retailerId,
        fromLabel: retailer.name,
        toId: vfNumberId,
        toLabel: vfPhone,
        createdByUid: createdByUid,
        notes: notes ?? 'Debt Settlement via VF Cash',
        timestamp: now,
      );

      // 2. Transaction for the isolated fee
      final feeTx = FinancialTransaction(
        type: FlowType.CREDIT_RETURN_FEE,
        amount: fees,
        fromId: retailerId,
        fromLabel: retailer.name,
        toId: vfNumberId,
        toLabel: vfPhone,
        createdByUid: createdByUid,
        notes: 'Credit Return Fee',
        timestamp: now,
      );

      // 3. CashTransaction for VF Number balance tracking (Total Received)
      final cashTxId = const Uuid().v4();
      final cashTxMap = {
        'id': cashTxId,
        'phoneNumber': vfPhone,
        'amount': totalReceived,
        'currency': 'EGP',
        'timestamp': now.toIso8601String(),
        'bybitOrderId': 'CRTN-${tx.id.substring(0, 8)}',
        'status': 'completed',
        'paymentMethod': 'VF Credit Return',
        'side': 1, // Incoming
        'chatHistory': 'Credit Return from ${retailer.name} (Amount: $amount, Fee: $fees)',
      };

      final updates = <String, dynamic>{
        'financial_ledger/${tx.id}': tx.toMap(),
        'transactions/$cashTxId': cashTxMap,
        'retailers/$retailerId/totalCollected': retailer.totalCollected + amount,
        'retailers/$retailerId/lastUpdatedAt': now.toIso8601String(),
      };
      if (fees > 0) {
        updates['financial_ledger/${feeTx.id}'] = feeTx.toMap();
      }

      await _db.ref().update(updates);
    } catch (e) {
      debugPrint('Credit Return error: $e');
      rethrow;
    } finally {
      _isCreditReturning = false;
      notifyListeners();
    }
  }

  /// Admin: Delete a transaction and reverse its financial impact.
  Future<void> deleteTransaction(FinancialTransaction tx) async {
    if (_isDeleting) return;
    _isDeleting = true;
    try {
      final futures = <Future<void>>[];

      // 1. Determine reversal impact based on transaction type
      if (tx.type == FlowType.COLLECT_CASH) {
        final retailerId = tx.fromId;
        final collectorId = tx.toId;
        final amount = tx.amount;

        if (retailerId != null) {
          final rIndex = _retailers.indexWhere((r) => r.id == retailerId);
          if (rIndex != -1) {
            final r = _retailers[rIndex];
            futures.add(_db.ref('retailers/$retailerId/totalCollected').set(r.totalCollected - amount));
          }
        }
        if (collectorId != null) {
          final cIndex = _collectors.indexWhere((c) => c.id == collectorId);
          if (cIndex != -1) {
            final c = _collectors[cIndex];
            futures.add(_db.ref('collectors/${c.id}/cashOnHand').set(c.cashOnHand - amount));
            futures.add(_db.ref('collectors/${c.id}/totalCollected').set(c.totalCollected - amount));
          }
        }
      } else if (tx.type == FlowType.DEPOSIT_TO_BANK) {
        final collectorId = tx.fromId;
        final bankId = tx.toId;
        final amount = tx.amount;

        if (bankId != null) {
          final bIndex = _bankAccounts.indexWhere((b) => b.id == bankId);
          if (bIndex != -1) {
            final b = _bankAccounts[bIndex];
            futures.add(_db.ref('bank_accounts/$bankId/balance').set(b.balance - amount));
          }
        }
        if (collectorId != null) {
          final cIndex = _collectors.indexWhere((c) => c.id == collectorId);
          if (cIndex != -1) {
            final c = _collectors[cIndex];
            futures.add(_db.ref('collectors/${c.id}/cashOnHand').set(c.cashOnHand + amount));
            futures.add(_db.ref('collectors/${c.id}/totalDeposited').set(c.totalDeposited - amount));
          }
        }
      } else if (tx.type == FlowType.DISTRIBUTE_VFCASH) {
        final retailerId = tx.toId;
        final amount = tx.amount;
        if (retailerId != null) {
          final rIndex = _retailers.indexWhere((r) => r.id == retailerId);
          if (rIndex != -1) {
            final r = _retailers[rIndex];
            futures.add(_db.ref('retailers/$retailerId/totalAssigned').set(r.totalAssigned - amount));
          }
        }
      } else if (tx.type == FlowType.FUND_BANK || tx.type == FlowType.BUY_USDT) {
        if (tx.type == FlowType.FUND_BANK) {
          final bankId = tx.toId;
          if (bankId != null) {
            final bIndex = _bankAccounts.indexWhere((b) => b.id == bankId);
            if (bIndex != -1) {
              futures.add(_db.ref('bank_accounts/$bankId/balance').set(_bankAccounts[bIndex].balance - tx.amount));
            }
          }
        } else {
          final bankId = tx.fromId;
          if (bankId != null) {
            final bIndex = _bankAccounts.indexWhere((b) => b.id == bankId);
            if (bIndex != -1) {
              futures.add(_db.ref('bank_accounts/$bankId/balance').set(_bankAccounts[bIndex].balance + tx.amount));
            }
          }
        }
      } else if (tx.type == FlowType.CREDIT_RETURN || tx.type == FlowType.CREDIT_RETURN_FEE) {
        final retailerId = tx.fromId;
        final amount = tx.amount;
        if (retailerId != null) {
          final rIndex = _retailers.indexWhere((r) => r.id == retailerId);
          if (rIndex != -1) {
            final r = _retailers[rIndex];
            futures.add(_db.ref('retailers/$retailerId/totalCollected').set(r.totalCollected - amount));
          }
        }
      } else if (tx.type == FlowType.BANK_DEDUCTION) {
        // Reversal: add the deducted amount back to the bank
        final bankId = tx.fromId;
        if (bankId != null) {
          final bIndex = _bankAccounts.indexWhere((b) => b.id == bankId);
          if (bIndex != -1) {
            futures.add(_db.ref('bank_accounts/$bankId/balance').set(_bankAccounts[bIndex].balance + tx.amount));
            futures.add(_db.ref('bank_accounts/$bankId/lastUpdatedAt').set(DateTime.now().toIso8601String()));
          }
        }
      }


      // 2. Delete the record from the ledger
      futures.add(_db.ref('financial_ledger/${tx.id}').remove());

      await Future.wait(futures);
    } catch (e) {
      debugPrint('Delete transaction error: $e');
      rethrow;
    } finally {
      _isDeleting = false;
    }
  }
}

