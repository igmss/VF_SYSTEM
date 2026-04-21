import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/bank_account.dart';
import '../models/retailer.dart';
import '../models/collector.dart';
import '../models/financial_transaction.dart';
import '../models/loan.dart';
import '../models/investor.dart';
import '../models/investor_profit_snapshot.dart';
import '../models/partner.dart';
import '../models/partner_profit_snapshot.dart';
import '../models/system_profit_snapshot.dart';
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
  List<Loan> _loans = [];
  List<Investor> _investors = [];
  Map<String, List<InvestorProfitSnapshot>> _investorSnapshots = {};
  List<Partner> _partners = [];
  Map<String, List<PartnerProfitSnapshot>> _partnerSnapshots = {};
  Map<String, SystemProfitSnapshot> _systemProfitSnapshots = {};
  Map<String, String> _userNames = {}; // UID -> Name
  double _usdtBalance = 0.0;     // USDT quantity in the exchange
  double _usdtLastPrice = 0.0;  // Last known EGP/USDT price (for EGP equivalent)
  double _openingCapital = 180000.0; // Partners Opening Capital

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
  bool _isIssuingLoan = false;
  bool _isRepayingLoan = false;

  bool get isIssuingLoan => _isIssuingLoan;
  bool get isRepayingLoan => _isRepayingLoan;

  bool _isInvestorLoading = false;
  bool _isPartnerLoading = false;
  bool get isInvestorLoading => _isInvestorLoading;
  bool get isPartnerLoading => _isPartnerLoading;

  double _totalInvestorPayable = 0.0;
  double _totalPartnerPayable = 0.0;
  double _totalInvestorVfFlow = 0.0;
  double _totalInvestorInstaFlow = 0.0;
  String? _error;

  StreamSubscription<DatabaseEvent>? _usdExchangeSub;
  StreamSubscription<DatabaseEvent>? _banksSub;
  StreamSubscription<DatabaseEvent>? _retailersSub;
  StreamSubscription<DatabaseEvent>? _collectorsSub;
  StreamSubscription<DatabaseEvent>? _ledgerSub;
  StreamSubscription<DatabaseEvent>? _loansSub;
  StreamSubscription<DatabaseEvent>? _investorsSub;
  StreamSubscription<DatabaseEvent>? _investorSnapshotsSub;
  StreamSubscription<DatabaseEvent>? _partnersSub;
  StreamSubscription<DatabaseEvent>? _partnerSnapshotsSub;
  StreamSubscription<DatabaseEvent>? _systemProfitSnapshotsSub;
  StreamSubscription<DatabaseEvent>? _openingCapitalSub;

  List<BankAccount> get bankAccounts => _bankAccounts;
  List<Investor> get investors => _investors;
  Map<String, List<InvestorProfitSnapshot>> get investorSnapshots => _investorSnapshots;
  List<Partner> get partners => _partners;
  Map<String, List<PartnerProfitSnapshot>> get partnerSnapshots => _partnerSnapshots;
  Map<String, SystemProfitSnapshot> get systemProfitSnapshots => _systemProfitSnapshots;
  List<Retailer> get retailers => _retailers;
  List<Collector> get collectors => _collectors;
  List<FinancialTransaction> get ledger => _ledger;
  List<Loan> get loans => _loans;

  /// USDT quantity held in USD Exchange
  double get usdtBalance => _usdtBalance;

  /// Last known EGP price per USDT
  double get usdtLastPrice => _usdtLastPrice;

  /// Partners Opening Capital (Seed money)
  double get openingCapital => _openingCapital;

  /// EGP equivalent of the USDT balance
  double get totalUsdExchangeBalance => _usdtBalance * (_usdtLastPrice > 0 ? _usdtLastPrice : 1);

  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, String> get userNames => _userNames;
  double get totalInvestorPayable => _totalInvestorPayable;
  double get totalPartnerPayable => _totalPartnerPayable;
  double get totalInvestorVfFlow => _totalInvestorVfFlow;
  double get totalInvestorInstaFlow => _totalInvestorInstaFlow;

  // ——————————————————————————————————————————————————————————————————————————
  //  Daily Retailer Totals  (computed from today's ledger entries)
  // ——————————————————————————————————————————————————————————————————————————

  /// Returns today's assigned VF cash amount for [retailerId].
  double retailerDailyVf(String retailerId) {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    return _ledger
        .where((t) =>
            t.type == FlowType.DISTRIBUTE_VFCASH &&
            t.toId == retailerId &&
            !t.timestamp.isBefore(todayStart))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  /// Returns today's assigned InstaPay amount for [retailerId].
  double retailerDailyInstaPay(String retailerId) {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    return _ledger
        .where((t) =>
            t.type == FlowType.DISTRIBUTE_INSTAPAY &&
            t.toId == retailerId &&
            !t.timestamp.isBefore(todayStart))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

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
      _retailers.fold(0, (sum, r) => sum + r.pendingDebt + r.instaPayPendingDebt);

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

  double get totalInstaPayProfit => _ledger
      .where((tx) => tx.type == FlowType.INSTAPAY_DIST_PROFIT)
      .fold(0.0, (sum, tx) => sum + tx.amount);

  double get totalOutstandingLoans =>
      _loans.fold(0.0, (sum, l) => sum + l.outstandingBalance);

  double get totalExpenses => _ledger
      .where((tx) =>
          tx.type == FlowType.EXPENSE_BANK ||
          tx.type == FlowType.EXPENSE_VFNUMBER ||
          tx.type == FlowType.EXPENSE_COLLECTOR)
      .fold(0.0, (sum, tx) => sum + tx.amount);

  List<FinancialTransaction> get expenseLedger => _ledger
      .where((tx) =>
          tx.type == FlowType.EXPENSE_BANK ||
          tx.type == FlowType.EXPENSE_VFNUMBER ||
          tx.type == FlowType.EXPENSE_COLLECTOR)
      .toList();

  double get totalInvestorCapital =>
      _investors.where((i) => i.status == 'active').fold(0.0, (s, i) => s + i.investedAmount);

  double get totalInvestorProfitOwed => _totalInvestorPayable;
  double get totalPartnerProfitOwed => _totalPartnerPayable;

  List<InvestorProfitSnapshot> validInvestorSnapshotsFor(String investorId) {
    final investor = _investors.cast<Investor?>().firstWhere(
          (i) => i?.id == investorId,
          orElse: () => null,
        );
    final startDate = investor?.investmentDate;
    return (_investorSnapshots[investorId] ?? [])
        .where((s) => s.isCurrentVersion)
        .where((s) => startDate == null || startDate.isEmpty || s.date.compareTo(startDate) >= 0)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  double partnerUnpaidTotalFor(String partnerId) {
    return (_partnerSnapshots[partnerId] ?? [])
        .where((s) => s.isCurrentVersion && !s.isPaid)
        .fold(0.0, (sum, s) => sum + s.partnerProfit);
  }


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
        getInvestorPerformance(), // Global summary
        getPartnerPerformance(),   // Global summary
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
        _ledger = map.entries
            .where((entry) => entry.value is Map)
            .map((entry) {
              final data = Map<String, dynamic>.from(entry.value as Map);
              return FinancialTransaction.fromMap(data, entry.key.toString());
            })
            .toList();
        _ledger.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      notifyListeners();
    });

    _loansSub?.cancel();
    _loansSub = _db.ref('loans').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        _loans = [];
      } else {
        final map = snap.value as Map;
        _loans = map.values
            .whereType<Map>()
            .map((v) => Loan.fromMap(Map<String, dynamic>.from(v)))
            .toList();
        _loans.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
      }
      notifyListeners();
    });

    _investorsSub?.cancel();
    _investorsSub = _db.ref('investors').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        _investors = [];
      } else {
        final map = snap.value as Map;
        _investors = map.values
            .whereType<Map>()
            .map((v) => Investor.fromMap(Map<String, dynamic>.from(v)))
            .toList();
        _investors.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      notifyListeners();
    });

    _investorSnapshotsSub?.cancel();
    _investorSnapshotsSub = _db.ref('investor_profit_snapshots').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        _investorSnapshots = {};
      } else {
        final Map<String, List<InvestorProfitSnapshot>> newSnapshots = {};
        final map = snap.value as Map;
        map.forEach((investorId, datesMap) {
          if (datesMap is Map) {
            final List<InvestorProfitSnapshot> snaps = datesMap.values
                .whereType<Map>()
                .map((v) => InvestorProfitSnapshot.fromMap(Map<String, dynamic>.from(v)))
                .toList();
            snaps.sort((a, b) => b.date.compareTo(a.date));
            newSnapshots[investorId.toString()] = snaps;
          }
        });
        _investorSnapshots = newSnapshots;
      }
      notifyListeners();
    });

    _partnersSub?.cancel();
    _partnersSub = _db.ref('system_config/partners').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        _partners = [];
      } else {
        final map = snap.value as Map;
        _partners = map.values
            .whereType<Map>()
            .map((v) => Partner.fromMap(Map<String, dynamic>.from(v)))
            .toList();
        _partners.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      notifyListeners();
    });

    _partnerSnapshotsSub?.cancel();
    _partnerSnapshotsSub =
        _db.ref('partner_profit_snapshots').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        _partnerSnapshots = {};
      } else {
        final Map<String, List<PartnerProfitSnapshot>> newSnapshots = {};
        final map = snap.value as Map;
        map.forEach((partnerId, datesMap) {
          if (datesMap is Map) {
            final List<PartnerProfitSnapshot> snaps = datesMap.values
                .whereType<Map>()
                .map((v) => PartnerProfitSnapshot.fromMap(
                    Map<String, dynamic>.from(v)))
                .toList();
            snaps.sort((a, b) => b.date.compareTo(a.date));
            newSnapshots[partnerId.toString()] = snaps;
          }
        });
        _partnerSnapshots = newSnapshots;
        debugPrint('[DEBUG] Provider: Loaded ${_partnerSnapshots.length} partners with snapshots.');
      }
      notifyListeners();
    });

    _systemProfitSnapshotsSub?.cancel();
    _systemProfitSnapshotsSub =
        _db.ref('system_profit_snapshots').onValue.listen((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null || snap.value is! Map) {
        _systemProfitSnapshots = {};
      } else {
        final map = snap.value as Map;
        final Map<String, SystemProfitSnapshot> newSnapshots = {};
        map.forEach((dateKey, value) {
          if (value is Map) {
            newSnapshots[dateKey.toString()] =
                SystemProfitSnapshot.fromMap(Map<String, dynamic>.from(value));
          }
        });
        _systemProfitSnapshots = newSnapshots;
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
      _db.ref('loans').get(),
      _db.ref('investors').get(),
      _db.ref('investor_profit_snapshots').get(),
      _db.ref('system_config/partners').get(),
      _db.ref('partner_profit_snapshots').get(),
      _db.ref('system_profit_snapshots').get(),
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
      _ledger = map.entries
          .where((entry) => entry.value is Map)
          .map((entry) {
            final data = Map<String, dynamic>.from(entry.value as Map);
            return FinancialTransaction.fromMap(data, entry.key.toString());
          })
          .toList();
      _ledger.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    final loansSnap = results[4];
    if (!loansSnap.exists || loansSnap.value == null || loansSnap.value is! Map) {
      _loans = [];
    } else {
      final map = loansSnap.value as Map;
      _loans = map.values
          .whereType<Map>()
          .map((v) => Loan.fromMap(Map<String, dynamic>.from(v)))
          .toList();
      _loans.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    }

    final investorsSnap = results[5];
    if (!investorsSnap.exists || investorsSnap.value == null || investorsSnap.value is! Map) {
      _investors = [];
    } else {
      final map = investorsSnap.value as Map;
      _investors = map.values
          .whereType<Map>()
          .map((v) => Investor.fromMap(Map<String, dynamic>.from(v)))
          .toList();
      _investors.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    final investorSnapshotsSnap = results[6];
    if (!investorSnapshotsSnap.exists || investorSnapshotsSnap.value == null || investorSnapshotsSnap.value is! Map) {
      _investorSnapshots = {};
    } else {
      final Map<String, List<InvestorProfitSnapshot>> newSnapshots = {};
      final map = investorSnapshotsSnap.value as Map;
      map.forEach((investorId, datesMap) {
        if (datesMap is Map) {
          final List<InvestorProfitSnapshot> snaps = datesMap.values
              .whereType<Map>()
              .map((v) => InvestorProfitSnapshot.fromMap(Map<String, dynamic>.from(v)))
              .toList();
          snaps.sort((a, b) => b.date.compareTo(a.date));
          newSnapshots[investorId.toString()] = snaps;
        }
      });
      _investorSnapshots = newSnapshots;
    }

    final partnersSnap = results[7];
    if (!partnersSnap.exists || partnersSnap.value == null || partnersSnap.value is! Map) {
      _partners = [];
    } else {
      final map = partnersSnap.value as Map;
      _partners = map.values
          .whereType<Map>()
          .map((v) => Partner.fromMap(Map<String, dynamic>.from(v)))
          .toList();
      _partners.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    final partnerSnapshotsSnap = results[8];
    if (!partnerSnapshotsSnap.exists || partnerSnapshotsSnap.value == null || partnerSnapshotsSnap.value is! Map) {
      _partnerSnapshots = {};
    } else {
      final Map<String, List<PartnerProfitSnapshot>> newSnapshots = {};
      final map = partnerSnapshotsSnap.value as Map;
      map.forEach((partnerId, datesMap) {
        if (datesMap is Map) {
          final List<PartnerProfitSnapshot> snaps = datesMap.values
              .whereType<Map>()
              .map((v) => PartnerProfitSnapshot.fromMap(Map<String, dynamic>.from(v)))
              .toList();
          snaps.sort((a, b) => b.date.compareTo(a.date));
          newSnapshots[partnerId.toString()] = snaps;
        }
      });
      _partnerSnapshots = newSnapshots;
    }

    final systemProfitSnapshotsSnap = results[9];
    if (!systemProfitSnapshotsSnap.exists || systemProfitSnapshotsSnap.value == null || systemProfitSnapshotsSnap.value is! Map) {
      _systemProfitSnapshots = {};
    } else {
      final map = systemProfitSnapshotsSnap.value as Map;
      final Map<String, SystemProfitSnapshot> newSnapshots = {};
      map.forEach((dateKey, value) {
        if (value is Map) {
          newSnapshots[dateKey.toString()] =
              SystemProfitSnapshot.fromMap(Map<String, dynamic>.from(value));
        }
      });
      _systemProfitSnapshots = newSnapshots;
    }

    notifyListeners();
  }

  // Used by mixins for targeted refreshes
  Future<void> _loadBankAccounts() async {
    final snap = await _db.ref('bank_accounts').get();
    if (snap.exists && snap.value is Map) {
      final map = snap.value as Map;
      _bankAccounts = map.values
          .whereType<Map>()
          .map((v) => BankAccount.fromMap(Map<String, dynamic>.from(v)))
          .toList();
      _bankAccounts.sort((a, b) {
        if (a.isDefaultForBuy == b.isDefaultForBuy) return a.bankName.compareTo(b.bankName);
        return a.isDefaultForBuy ? -1 : 1;
      });
      notifyListeners();
    }
  }

  Future<void> _loadLedger() async {
    final snap = await _db.ref('financial_ledger').get();
    if (snap.exists && snap.value is Map) {
      final map = snap.value as Map;
      _ledger = map.entries
          .where((entry) => entry.value is Map)
          .map((entry) => FinancialTransaction.fromMap(Map<String, dynamic>.from(entry.value as Map), entry.key.toString()))
          .toList();
      _ledger.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      notifyListeners();
    }
  }

  Future<void> _loadRetailers() async {
    final snap = await _db.ref('retailers').get();
    if (snap.exists && snap.value is Map) {
      final map = snap.value as Map;
      _retailers = map.values
          .whereType<Map>()
          .map((v) => Retailer.fromMap(Map<String, dynamic>.from(v)))
          .where((r) => r.isActive)
          .toList();
      _retailers.sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
    }
  }

  Future<void> _loadCollectors() async {
    final snap = await _db.ref('collectors').get();
    if (snap.exists && snap.value is Map) {
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
      notifyListeners();
    }
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Future<void> _addUsdtBalance(double usdtQty, double price) async {
    _usdtBalance += usdtQty;
    if (price > 0) _usdtLastPrice = price;
    await _db.ref('usd_exchange').update({
      'usdtBalance': _usdtBalance,
      'balance': _usdtBalance,
      'lastPrice': _usdtLastPrice,
      'lastUpdatedAt': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  Future<void> _subtractUsdtBalance(double usdtQty, double price) async {
    _usdtBalance = (_usdtBalance - usdtQty).clamp(0.0, double.infinity);
    if (price > 0) _usdtLastPrice = price;
    await _db.ref('usd_exchange').update({
      'usdtBalance': _usdtBalance,
      'balance': _usdtBalance,
      'lastPrice': _usdtLastPrice,
      'lastUpdatedAt': DateTime.now().toIso8601String(),
    });
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
    _loansSub?.cancel();
    _investorsSub?.cancel();
    _investorSnapshotsSub?.cancel();
    _partnersSub?.cancel();
    _partnerSnapshotsSub?.cancel();
    _systemProfitSnapshotsSub?.cancel();
    super.dispose();
  }

  Future<void> setUsdExchangeBalance(double usdtAmount) async {
    _usdtBalance = usdtAmount;
    await _db.ref('usd_exchange/usdtBalance').set(usdtAmount);
    await _db.ref('usd_exchange/balance').set(usdtAmount);
    await _db.ref('usd_exchange/lastUpdatedAt').set(DateTime.now().toIso8601String());
    notifyListeners();
  }


  // ——————————————————————————————————————————————————————————————————————————
  //  Load Stubs (Used by loadAll)
  // ——————————————————————————————————————————————————————————————————————————


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

  // ——————————————————————————————————————————————————————————————————————————
  //  Loan Operations
  // ——————————————————————————————————————————————————————————————————————————

  Future<void> issueLoan({
    required LoanSourceType sourceType,
    required String sourceId,
    required String borrowerName,
    String? borrowerPhone,
    required double amount,
    String? notes,
    required String createdByUid,
  }) async {
    if (_isIssuingLoan) return;
    _isIssuingLoan = true;
    notifyListeners();

    try {
      final callable = _functions.httpsCallable('issueLoan');
      await callable.call({
        'sourceType': sourceType.name,
        'sourceId': sourceId,
        'borrowerName': borrowerName,
        'borrowerPhone': borrowerPhone,
        'amount': amount,
        'notes': notes,
        'createdByUid': createdByUid,
      });
      await loadAll();
    } catch (e) {
      debugPrint('Issue loan error: $e');
      rethrow;
    } finally {
      _isIssuingLoan = false;
      notifyListeners();
    }
  }

  Future<void> recordLoanRepayment({
    required String loanId,
    required double amount,
    required String createdByUid,
  }) async {
    if (_isRepayingLoan) return;
    _isRepayingLoan = true;
    notifyListeners();

    try {
      final callable = _functions.httpsCallable('recordLoanRepayment');
      await callable.call({
        'loanId': loanId,
        'amount': amount,
        'createdByUid': createdByUid,
      });
      await loadAll();
    } catch (e) {
      debugPrint('Record loan repayment error: $e');
      rethrow;
    } finally {
      _isRepayingLoan = false;
      notifyListeners();
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Expense Operations
  // ──────────────────────────────────────────────────────────────────────────

  bool _isRecordingExpense = false;
  bool get isRecordingExpense => _isRecordingExpense;

  Future<void> recordExpense({
    required String sourceId,
    required double amount,
    String? category,
    String? notes,
    required String createdByUid,
  }) async {
    if (_isRecordingExpense) return;
    _isRecordingExpense = true;
    notifyListeners();

    try {
      final callable = _functions.httpsCallable('recordExpense');
      await callable.call({
        'sourceId': sourceId,
        'amount': amount,
        'category': category,
        'notes': notes,
        'createdByUid': createdByUid,
      });
      await loadAll();
    } catch (e) {
      debugPrint('Record expense error: $e');
      rethrow;
    } finally {
      _isRecordingExpense = false;
      notifyListeners();
    }
  }

  // ——————————————————————————————————————————————————————————————————————————
  //  Investors & Profit Sharing Data
  // ——————————————————————————————————————————————————————————————————————————


  Future<void> recordInvestorCapital({
    required String name,
    required String phone,
    required double investedAmount,
    required double initialBusinessCapital,
    required double profitSharePercent,
    required String investmentDate,
    required int periodDays,
    required String bankAccountId,
    String? notes,
    required String createdByUid,
  }) async {
    _isInvestorLoading = true;
    notifyListeners();
    try {
      final callable = _functions.httpsCallable('recordInvestorCapital');
      await callable.call({
        'name': name,
        'phone': phone,
        'investedAmount': investedAmount,
        'initialBusinessCapital': initialBusinessCapital,
        'profitSharePercent': profitSharePercent,
        'investmentDate': investmentDate,
        'periodDays': periodDays,
        'bankAccountId': bankAccountId,
        'notes': notes,
        'createdByUid': createdByUid,
      });
      await loadAll();
    } catch (e) {
      debugPrint('Record investor capital error: $e');
      rethrow;
    } finally {
      _isInvestorLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> getInvestorPerformance({
    String? investorId,
  }) async {
    try {
      final callable = _functions.httpsCallable('getInvestorPerformance');
      final result = await callable.call({
        'investorId': investorId,
      });
      final data = Map<String, dynamic>.from(result.data);
      if (investorId == null) {
        _totalInvestorPayable = (data['totalPayable'] ?? 0.0).toDouble();
        _totalInvestorVfFlow = (data['totalVfFlow'] ?? 0.0).toDouble();
        _totalInvestorInstaFlow = (data['totalInstaFlow'] ?? 0.0).toDouble();
      }
      return data;
    } catch (e) {
      debugPrint('Get investor performance error: $e');
      rethrow;
    }
  }

  Future<void> payInvestorProfit({
    required String investorId,
    required double amount,
    required String bankAccountId,
    required String createdByUid,
    String? notes,
  }) async {
    _isInvestorLoading = true;
    notifyListeners();
    try {
      final callable = _functions.httpsCallable('payInvestorProfit');
      await callable.call({
        'investorId': investorId,
        'amount': amount,
        'bankAccountId': bankAccountId,
        'createdByUid': createdByUid,
        'notes': notes,
      });
      await loadAll();
    } catch (e) {
      debugPrint('Pay investor profit error: $e');
      rethrow;
    } finally {
      _isInvestorLoading = false;
      notifyListeners();
    }
  }

  Future<void> withdrawInvestorCapital({
    required String investorId,
    required double amount,
    required String bankAccountId,
    required String createdByUid,
    String? notes,
  }) async {
    _isInvestorLoading = true;
    notifyListeners();
    try {
      final callable = _functions.httpsCallable('withdrawInvestorCapital');
      await callable.call({
        'investorId': investorId,
        'amount': amount,
        'bankAccountId': bankAccountId,
        'notes': notes,
        'createdByUid': createdByUid,
      });
      await loadAll();
    } catch (e) {
      debugPrint('Withdraw investor capital error: $e');
      rethrow;
    } finally {
      _isInvestorLoading = false;
      notifyListeners();
    }
  }

  Future<void> setOpeningCapital(double value) async {
    try {
      final todayKey = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD
      await Future.wait([
        _db.ref('system_config/openingCapital').set(value),
        _db.ref('system_config/openingCapitalHistory/$todayKey').set(value),
      ]);
    } catch (e) {
      debugPrint('Set opening capital error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> calculateSystemProfitSnapshot({
    required String date,
    required int workingDays,
  }) async {
    _isPartnerLoading = true;
    notifyListeners();
    try {
      final callable = _functions.httpsCallable('calculateSystemProfitSnapshot');
      final result = await callable.call({
        'date': date,
        'workingDays': workingDays,
      });
      await loadAll();
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      debugPrint('Calculate system profit snapshot error: $e');
      rethrow;
    } finally {
      _isPartnerLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> rebuildProfitSnapshots({
    required String startDate,
    required String endDate,
    bool resetPaidFlags = false,
  }) async {
    _isPartnerLoading = true;
    notifyListeners();
    try {
      final callable = _functions.httpsCallable('rebuildProfitSnapshots');
      final result = await callable.call({
        'startDate': startDate,
        'endDate': endDate,
        'resetPaidFlags': resetPaidFlags,
      });
      await loadAll();
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      debugPrint('Rebuild profit snapshots error: $e');
      rethrow;
    } finally {
      _isPartnerLoading = false;
      notifyListeners();
    }
  }

  // ——————————————————————————————————————————————————————————————————————————
  //  Partner Profit Sharing Operations
  // ——————————————————————————————————————————————————————————————————————————


  Future<Map<String, dynamic>> getPartnerPerformance() async {
    try {
      final callable = _functions.httpsCallable('getPartnerPerformance');
      final result = await callable.call();
      final data = Map<String, dynamic>.from(result.data);
      _totalPartnerPayable = (data['totalPayable'] ?? 0.0).toDouble();
      return data;
    } catch (e) {
      debugPrint('Get partner performance error: $e');
      rethrow;
    }
  }

  Future<void> payPartnerProfit({
    required String partnerId,
    required double amount,
    required String paymentSourceType,
    required String paymentSourceId,
    required String createdByUid,
    String? notes,
  }) async {
    _isPartnerLoading = true;
    notifyListeners();
    try {
      final callable = _functions.httpsCallable('payPartnerProfit');
      await callable.call({
        'partnerId': partnerId,
        'amount': amount,
        'paymentSourceType': paymentSourceType,
        'paymentSourceId': paymentSourceId,
        'createdByUid': createdByUid,
        'notes': notes,
      });
      await loadAll();
    } catch (e) {
      debugPrint('Pay partner profit error: $e');
      rethrow;
    } finally {
      await getInvestorPerformance();
      await getPartnerPerformance();
      _isPartnerLoading = false;
      notifyListeners();
    }
  }

  Future<void> seedPartners() async {
    _isPartnerLoading = true;
    notifyListeners();
    try {
      final callable = _functions.httpsCallable('seedPartners');
      await callable.call();
      await loadAll();
    } catch (e) {
      debugPrint('Seed partners error: $e');
      rethrow;
    } finally {
      _isPartnerLoading = false;
      notifyListeners();
    }
  }

  Future<void> savePartner(Partner partner) async {
    _isPartnerLoading = true;
    notifyListeners();
    try {
      final callable = _functions.httpsCallable('savePartner');
      await callable.call({
        'partner': partner.toMap(),
      });
      await loadAll();
    } catch (e) {
      debugPrint('Save partner error: $e');
      rethrow;
    } finally {
      _isPartnerLoading = false;
      notifyListeners();
    }
  }

  Future<void> setPartnerStatus(String partnerId, String status) async {
    _isPartnerLoading = true;
    notifyListeners();
    try {
      final callable = _functions.httpsCallable('setPartnerStatus');
      await callable.call({
        'partnerId': partnerId,
        'status': status,
      });
      await loadAll();
    } catch (e) {
      debugPrint('Set partner status error: $e');
      rethrow;
    } finally {
      _isPartnerLoading = false;
      notifyListeners();
    }
  }
}
