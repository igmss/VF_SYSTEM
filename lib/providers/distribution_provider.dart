import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flutter/foundation.dart';

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
  final sb.SupabaseClient _supabase = sb.Supabase.instance.client;

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
  double _usdtBalance = 0.0;
  double _usdtLastPrice = 0.0;
  double _openingCapital = 180000.0;

  bool _isLoading = false;
  bool _isListenersInitialized = false;

  // Per-action in-flight flags
  bool _isDistributing = false;
  bool _isCollecting = false;
  bool _isDepositing = false;
  bool _isCorrecting = false;
  bool _isCreditReturning = false;
  bool _isInternalTransferring = false;
  bool _isIssuingLoan = false;
  bool _isRepayingLoan = false;
  bool _isInvestorLoading = false;
  bool _isPartnerLoading = false;
  bool _isDeleting = false;

  bool get isDistributing => _isDistributing;
  bool get isCollecting => _isCollecting;
  bool get isDepositing => _isDepositing;
  bool get isCreditReturning => _isCreditReturning;
  bool get isInternalTransferring => _isInternalTransferring;
  bool get isIssuingLoan => _isIssuingLoan;
  bool get isRepayingLoan => _isRepayingLoan;
  bool get isInvestorLoading => _isInvestorLoading;
  bool get isPartnerLoading => _isPartnerLoading;
  bool get isDeleting => _isDeleting;

  double _totalInvestorPayable = 0.0;
  double _totalPartnerPayable = 0.0;
  Map<String, dynamic> _partnerPerformance = {};
  Map<String, dynamic> _investorPerformance = {};
  Map<String, Map<String, dynamic>> _investorPerformanceCache = {};
  double _totalInvestorVfFlow = 0.0;
  double _totalInvestorInstaFlow = 0.0;
  String? _error;

  // Supabase Stream Subscriptions
  StreamSubscription? _usdExchangeSub;
  StreamSubscription? _banksSub;
  StreamSubscription? _retailersSub;
  StreamSubscription? _collectorsSub;
  StreamSubscription? _ledgerSub;
  StreamSubscription? _loansSub;
  StreamSubscription? _investorsSub;
  StreamSubscription? _investorSnapshotsSub;
  StreamSubscription? _partnersSub;
  StreamSubscription? _partnerSnapshotsSub;
  StreamSubscription? _systemProfitSnapshotsSub;

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

  double get usdtBalance => _usdtBalance;
  double get usdtLastPrice => _usdtLastPrice;
  double get openingCapital => _openingCapital;
  double get totalUsdExchangeBalance => _usdtBalance * (_usdtLastPrice > 0 ? _usdtLastPrice : 1);

  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, String> get userNames => _userNames;
  double get totalInvestorPayable => _totalInvestorPayable;
  double get totalPartnerPayable => _totalPartnerPayable;
  Map<String, dynamic> get partnerPerformance => _partnerPerformance;
  Map<String, dynamic> get investorPerformance => _investorPerformance;
  double get totalInvestorVfFlow => _totalInvestorVfFlow;
  double get totalInvestorInstaFlow => _totalInvestorInstaFlow;
  
  void invalidateInvestorPerformance(String investorId) {
    _investorPerformanceCache.remove(investorId);
  }

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

  double get totalBankBalance => _bankAccounts.fold(0, (sum, b) => sum + b.balance);
  BankAccount? get defaultBuyBank {
    try {
      return _bankAccounts.firstWhere((a) => a.isDefaultForBuy);
    } catch (_) {
      return _bankAccounts.isNotEmpty ? _bankAccounts.first : null;
    }
  }
  double get totalRetailerDebt => _retailers.fold(0, (sum, r) => sum + r.pendingDebt + r.instaPayPendingDebt);
  double get totalCollectorCash => _collectors.fold(0, (sum, c) => sum + c.cashOnHand);
  double get totalTransferFees => _ledger.where((tx) => tx.type == FlowType.EXPENSE_VFCASH_FEE).fold(0.0, (sum, tx) => sum + tx.amount);
  double get totalVfDepositProfit => _ledger.where((tx) => tx.type == FlowType.VFCASH_RETAIL_PROFIT).fold(0.0, (sum, tx) => sum + tx.amount);
  double get totalCreditReturnProfit => _ledger.where((tx) => tx.type == FlowType.CREDIT_RETURN_FEE).fold(0.0, (sum, tx) => sum + tx.amount);
  double get totalInstaPayProfit => _ledger.where((tx) => tx.type == FlowType.INSTAPAY_DIST_PROFIT).fold(0.0, (sum, tx) => sum + tx.amount);
  double get totalOutstandingLoans => _loans.fold(0.0, (sum, l) => sum + l.outstandingBalance);
  double get totalExpenses => _ledger.where((tx) => tx.type == FlowType.EXPENSE_BANK || tx.type == FlowType.EXPENSE_VFNUMBER || tx.type == FlowType.EXPENSE_COLLECTOR).fold(0.0, (sum, tx) => sum + tx.amount);
  List<FinancialTransaction> get expenseLedger => _ledger.where((tx) => tx.type == FlowType.EXPENSE_BANK || tx.type == FlowType.EXPENSE_VFNUMBER || tx.type == FlowType.EXPENSE_COLLECTOR).toList();
  double get totalInvestorCapital => _investors.where((i) => i.status == 'active').fold(0.0, (s, i) => s + i.investedAmount);
  double get totalInvestorProfitOwed => _totalInvestorPayable;
  double get totalPartnerProfitOwed => _totalPartnerPayable;

  List<InvestorProfitSnapshot> validInvestorSnapshotsFor(String investorId) {
    final investor = _investors.cast<Investor?>().firstWhere((i) => i?.id == investorId, orElse: () => null);
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

  Future<void> loadAll() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _initializeListeners();
      // 1. Fetch base data first
      await Future.wait([
        _fetchAllLedgerEntries(),
        _refreshOperationalData(),
        _refreshUsdExchangeData(),
      ]);
      // 2. Now calculate performance based on that data
      await Future.wait([
        getInvestorPerformance(),
        getPartnerPerformance(),
      ]);
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

  /// Fetches ALL financial_ledger rows in batches of 1000 to bypass Supabase's
  /// default 1000-row stream limit.
  Future<void> _fetchAllLedgerEntries() async {
    try {
      const pageSize = 1000;
      int offset = 0;
      final List<FinancialTransaction> all = [];
      while (true) {
        final rows = await _supabase
            .from('financial_ledger')
            .select()
            .order('timestamp', ascending: false)
            .range(offset, offset + pageSize - 1);
        final batch = (rows as List).map((v) => FinancialTransaction.fromMap({
          'id': v['id'],
          'type': v['type'],
          'amount': v['amount'],
          'fromId': v['from_id'],
          'fromLabel': v['from_label'],
          'toId': v['to_id'],
          'toLabel': v['to_label'],
          'createdByUid': v['created_by_uid'],
          'notes': v['notes'],
          'timestamp': v['timestamp'],
          'bybitOrderId': v['bybit_order_id'],
          'relatedLedgerId': v['related_ledger_id'],
          'generatedTransactionId': v['generated_transaction_id'],
          'transferredAmount': v['transferred_amount'],
          'feeAmount': v['fee_amount'],
          'feeRatePer1000': v['fee_rate_per_1000'],
          'collectedPortion': v['collected_portion'],
          'creditPortion': v['credit_portion'],
          'usdtPrice': v['usdt_price'],
          'usdtQuantity': v['usdt_quantity'],
          'profitPer1000': v['profit_per_1000'],
          'category': v['category'],
          'paymentMethod': v['payment_method'],
        }, v['id'])).toList();
        all.addAll(batch);
        if (batch.length < pageSize) break; // last page
        offset += pageSize;
      }
      _ledger = all;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching ledger: $e');
    }
  }

  void _initializeListeners() {
    if (_isListenersInitialized) return;
    _isListenersInitialized = true;

    _usdExchangeSub = _supabase.from('usd_exchange').stream(primaryKey: ['id']).listen((rows) {
      if (rows.isNotEmpty) {
        final data = rows.first;
        _usdtBalance = _asDouble(data['usdt_balance']);
        _usdtLastPrice = _asDouble(data['last_price']);
      }
      notifyListeners();
    });

    _banksSub = _supabase.from('bank_accounts').stream(primaryKey: ['id']).listen((rows) {
      final uniqueRows = {for (var v in rows) v['id']: v};
      _bankAccounts = uniqueRows.values.map((v) => BankAccount.fromMap({
        'id': v['id'],
        'bankName': v['bank_name'],
        'accountNumber': v['account_number'],
        'accountHolder': v['account_holder'],
        'balance': v['balance'],
        'isDefaultForBuy': v['is_default_for_buy'],
        'lastUpdatedAt': v['last_updated_at'],
      })).toList();
      _bankAccounts.sort((a, b) => a.bankName.compareTo(b.bankName));
      notifyListeners();
    });

    _retailersSub = _supabase.from('retailers').stream(primaryKey: ['id']).listen((rows) {
      final uniqueRows = {for (var v in rows) v['id']: v};
      _retailers = uniqueRows.values.map((v) => Retailer.fromMap({
        'id': v['id'],
        'name': v['name'],
        'phone': v['phone'],
        'assignedCollectorId': v['assigned_collector_id'],
        'discountPer1000': v['discount_per_1000'],
        'instaPayProfitPer1000': v['insta_pay_profit_per_1000'],
        'totalAssigned': v['total_assigned'],
        'totalCollected': v['total_collected'],
        'instaPayTotalAssigned': v['insta_pay_total_assigned'],
        'instaPayTotalCollected': v['insta_pay_total_collected'],
        'instaPayPendingDebt': v['insta_pay_pending_debt'],
        'pending_debt': v['pending_debt'], // Ensure key matches exactly
        'credit': v['credit'],
        'area': v['area'],
        'isActive': v['is_active'],
      })).where((r) => r.isActive).toList();
      _retailers.sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
    });

    _collectorsSub = _supabase.from('collectors').stream(primaryKey: ['id']).listen((rows) {
      _collectors = rows.map((v) => Collector.fromMap({
        'id': v['id'],
        'uid': v['uid'],
        'name': v['name'],
        'phone': v['phone'],
        'email': v['email'],
        'cashOnHand': v['cash_on_hand'],
        'cashLimit': v['cash_limit'],
        'totalCollected': v['total_collected'],
        'totalDeposited': v['total_deposited'],
        'isActive': v['is_active'],
      })).where((c) => c.isActive).toList();
      _collectors.sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
    });

    // Use paginated fetch instead of .stream() to bypass the 1000-row default limit
    _fetchAllLedgerEntries();

    // Subscribe to ALL events on financial_ledger to refresh when anything changes
    _supabase.channel('ledger_changes')
      .onPostgresChanges(
        event: sb.PostgresChangeEvent.all,
        schema: 'public',
        table: 'financial_ledger',
        callback: (_) => _fetchAllLedgerEntries(),
      )
      .subscribe();

    _loansSub = _supabase.from('loans').stream(primaryKey: ['id']).listen((rows) {
      _loans = rows.map((v) => Loan.fromMap({
        'id': v['id'],
        'borrowerName': v['borrower_name'],
        'borrowerPhone': v['borrower_phone'],
        'principalAmount': v['principal_amount'],
        'amountRepaid': v['amount_repaid'],
        'sourceType': v['source_type'],
        'sourceId': v['source_id'],
        'sourceLabel': v['source_label'],
        'status': v['status'],
        'issuedAt': v['issued_at'],
        'repaidAt': v['repaid_at'],
        'lastUpdatedAt': v['last_updated_at'],
        'notes': v['notes'],
        'createdByUid': v['created_by_uid'],
      })).toList();
      _loans.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
      notifyListeners();
    });

    _investorsSub = _supabase.from('investors').stream(primaryKey: ['id']).listen((rows) {
      _investors = rows.map((v) => Investor.fromMap({
        'id': v['id'],
        'name': v['name'],
        'phone': v['phone'],
        'investedAmount': v['invested_amount'],
        'halfInvestedAmount': v['half_invested_amount'],
        'initialBusinessCapital': v['initial_business_capital'],
        'cumulativeCapitalBefore': v['cumulative_capital_before'],
        'halfCumulativeCapital': v['half_cumulative_capital'],
        'profitSharePercent': v['profit_share_percent'],
        'investmentDate': v['investment_date']?.toString(),
        'periodDays': v['period_days'],
        'status': v['status'],
        'totalProfitPaid': v['total_profit_paid'],
        'capitalHistory': v['capital_history'],
        'notes': v['notes'],
        'createdByUid': v['created_by_uid'],
        'createdAt': v['created_at'],
        'lastPaidAt': v['last_paid_at'],
      })).toList();
      _investors.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _investorPerformanceCache.clear();
      notifyListeners();
    });
    
    _partnersSub = _supabase.from('partners').stream(primaryKey: ['id']).listen((rows) {
      _partners = rows.map((v) => Partner.fromMap({
        'id': v['id'],
        'name': v['name'],
        'sharePercent': v['share_percent'],
        'status': v['status'],
        'totalProfitPaid': v['total_profit_paid'],
        'createdAt': v['created_at'],
        'updatedAt': v['updated_at'],
        'lastPaidAt': v['last_paid_at'],
      })).toList();
      _partners.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _partnerPerformance = {};
      notifyListeners();
    });

    _systemProfitSnapshotsSub = _supabase.from('system_profit_snapshots').stream(primaryKey: ['date_key']).listen((rows) {
      debugPrint('=== STREAM EVENT: system_profit_snapshots ===');
      debugPrint('Rows count: ${rows.length}');
      if (rows.isNotEmpty) {
        debugPrint('First row keys: ${rows.first.keys.toList()}');
        debugPrint('First row date_key: ${rows.first['date_key']}');
        debugPrint('First row opening_capital: ${rows.first['opening_capital']}');
        debugPrint('First row total_flow: ${rows.first['total_flow']}');
      }
      _systemProfitSnapshots = {for (var v in rows) v['date_key']?.toString() ?? '': SystemProfitSnapshot.fromMap(v)};
      debugPrint('Loaded ${_systemProfitSnapshots.length} system snapshots');
      if (_systemProfitSnapshots.isNotEmpty) {
        final firstSnap = _systemProfitSnapshots.values.first;
        debugPrint('First snap date: ${firstSnap.date}, flow: ${firstSnap.totalFlow}, openingCap: ${firstSnap.openingCapital}');
      }
      notifyListeners();
    });
  }

  Future<void> _refreshOperationalData() async {}
  Future<void> _refreshUsdExchangeData() async {
    final response = await _supabase.from('usd_exchange').select().eq('id', 1).maybeSingle();
    if (response != null) {
      _usdtBalance = _asDouble(response['usdt_balance']);
      _usdtLastPrice = _asDouble(response['last_price']);
      notifyListeners();
    }
  }

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Future<void> _addUsdtBalance(double usdtQty, double price) async {
    await _supabase.rpc('update_usd_exchange', params: {'p_balance_delta': usdtQty, 'p_new_price': price});
  }

  Future<void> _subtractUsdtBalance(double usdtQty, double price) async {
    await _supabase.rpc('update_usd_exchange', params: {'p_balance_delta': -usdtQty, 'p_new_price': price});
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
    await _supabase.from('usd_exchange').update({'usdt_balance': usdtAmount}).eq('id', 1);
  }

  // Waterfall Profit Calculation Logic (Dart Implementation of profitEngine.js)
  double _calculateInvestorProfit({
    required double totalFlow,
    required double vfFlow,
    required double instaFlow,
    required double hurdle,
    required double halfCap,
    required double vfNetPer1000,
    required double instaNetPer1000,
    required double sharePercent,
  }) {
    if (totalFlow <= hurdle) return 0.0;
    
    final grossExcess = totalFlow - hurdle;
    final allowedExcess = grossExcess < halfCap ? grossExcess : halfCap;
    
    final ratio = totalFlow > 0 ? vfFlow / totalFlow : 0;
    final vfExcess = allowedExcess * ratio;
    final instaExcess = allowedExcess * (1 - ratio);
    
    final shareFactor = sharePercent / 100.0;
    final vfProfit = (vfExcess / 1000.0) * (vfNetPer1000 > 0 ? vfNetPer1000 : 0) * shareFactor;
    final instaProfit = (instaExcess / 1000.0) * (instaNetPer1000 > 0 ? instaNetPer1000 : 0) * shareFactor;
    
    return vfProfit + instaProfit;
  }

  Future<Map<String, dynamic>> getInvestorPerformance({String? investorId}) async {
    final isPerInvestor = investorId != null;
    if (!isPerInvestor) {
      _isInvestorLoading = true;
      Future.microtask(() => notifyListeners());
    }
    try {
      if (investorId != null) {
        final cached = _investorPerformanceCache[investorId];
        if (cached != null) {
          return cached;
        }
      }

      final response = await _supabase.functions.invoke('get-investor-performance', body: {
        if (investorId != null) 'investor_id': investorId,
      });

      if (response.data != null) {
        final data = Map<String, dynamic>.from(response.data);

        if (investorId != null) {
          _investorPerformanceCache[investorId] = data;
          return data;
        }

        final performance = data['performance'] as List? ?? [];
        double totalEarned = 0.0;
        double totalPaid = 0.0;
        double totalVfFlow = 0.0;
        double totalInstaFlow = 0.0;

        for (final inv in performance) {
          totalEarned += (inv['totalEarned'] as num?)?.toDouble() ?? 0.0;
          totalPaid += (inv['totalPaid'] as num?)?.toDouble() ?? 0.0;
          totalVfFlow += (inv['totalVfFlow'] as num?)?.toDouble() ?? 0.0;
          totalInstaFlow += (inv['totalInstaFlow'] as num?)?.toDouble() ?? 0.0;
        }

        final payableBalance = (totalEarned - totalPaid).clamp(0.0, double.infinity);
        _totalInvestorPayable = payableBalance;
        _totalInvestorVfFlow = (data['totalVfFlow'] as num?)?.toDouble() ?? totalVfFlow;
        _totalInvestorInstaFlow = (data['totalInstaFlow'] as num?)?.toDouble() ?? totalInstaFlow;
        _investorPerformance = {
          'totalEarned': totalEarned,
          'totalPaid': totalPaid,
          'payableBalance': payableBalance,
          'performance': performance,
          'totalPayable': _totalInvestorPayable,
        };

        if (!isPerInvestor) {
          _isInvestorLoading = false;
          Future.microtask(() => notifyListeners());
        }
        return _investorPerformance;
      }

      if (!isPerInvestor) {
        _isInvestorLoading = false;
        Future.microtask(() => notifyListeners());
      }
      return {};
    } catch (e) {
      debugPrint('Error getInvestorPerformance: $e');
      if (!isPerInvestor) {
        _isInvestorLoading = false;
        Future.microtask(() => notifyListeners());
      }
      return {};
    }
  }

  Future<Map<String, dynamic>> getPartnerPerformance() async {
    _isPartnerLoading = true;
    Future.microtask(() => notifyListeners());
    try {
      final response = await _supabase.functions.invoke('get-partner-performance', body: {});
      final data = response.data is Map ? Map<String, dynamic>.from(response.data) : <String, dynamic>{};

      _partnerPerformance = data;
      _totalPartnerPayable = _asDouble(data['totalPayable']);

      _isPartnerLoading = false;
      Future.microtask(() => notifyListeners());

      return _partnerPerformance;
    } catch (e) {
      debugPrint('Error getPartnerPerformance: $e');
      _isPartnerLoading = false;
      Future.microtask(() => notifyListeners());
      return {};
    }
  }
  
  // Helpers
  Collector? getMyCollector(String uid) => _collectors.where((c) => c.id == uid || c.uid == uid).firstOrNull;
  List<Retailer> getMyRetailers(String collectorUid) => _retailers.where((r) => r.assignedCollectorId == collectorUid).toList();

  Future<void> setOpeningCapital(double capital) async {
    _openingCapital = capital;
    await _supabase.from('system_config').upsert({'key': 'opening_capital', 'value': capital});
  }

  Future<Map<String, dynamic>?> getSystemConfig(String key) async {
    try {
      final result = await _supabase.from('system_config').select('value').eq('key', key).maybeSingle();
      if (result != null) {
        return Map<String, dynamic>.from(result['value'] ?? {});
      }
    } catch (e) {
      debugPrint('Error getSystemConfig: $e');
    }
    return null;
  }

  Future<void> setSystemConfig(String key, Map<String, dynamic> value) async {
    await _supabase.from('system_config').upsert({'key': key, 'value': value});
  }

  Future<void> savePartner(Partner partner) async {
    await _supabase.from('partners').upsert({
      'id': partner.id, 'name': partner.name, 'share_percent': partner.sharePercent, 'status': partner.status
    });
  }

  Future<void> payPartnerProfit({
    required String partnerId, 
    required double amount, 
    required String paymentSourceType,
    required String paymentSourceId,
    required String createdByUid,
    String? notes,
  }) async {
    await _supabase.rpc('pay_partner_profit', params: {
      'p_partner_id': partnerId, 
      'p_amount': amount, 
      'p_method': paymentSourceType == 'bank' ? 'BANK' : 'VF', 
      'p_source_id': paymentSourceId,
      'p_created_by_uid': createdByUid,
      'p_notes': notes
    });
    _partnerPerformance = {};
    notifyListeners();
  }

  Future<void> seedPartners() async {
    await _supabase.functions.invoke('get-partner-performance', body: {'action': 'seed'});
  }

  Future<void> setPartnerStatus(String id, String status) async {
    await _supabase.from('partners').update({'status': status}).eq('id', id);
  }

  Future<void> recordInvestorCapital({
    String? investorId,
    String? name,
    String? phone,
    double? investedAmount,
    double? amount,
    double? initialBusinessCapital,
    double? profitSharePercent,
    String? investmentDate,
    int? periodDays,
    String? bankAccountId,
    String? notes,
    required String createdByUid,
  }) async {
    if (name != null) {
      // Create new investor
      await _supabase.functions.invoke('create-investor', body: {
        'name': name,
        'phone': phone,
        'investedAmount': investedAmount ?? amount ?? 0,
        'initialBusinessCapital': initialBusinessCapital ?? 0,
        'profitSharePercent': profitSharePercent ?? 0,
        'investmentDate': investmentDate,
        'periodDays': periodDays ?? 30,
        'bankAccountId': bankAccountId,
        'notes': notes,
        'createdByUid': createdByUid,
      });
    } else {
      // Add capital to existing
      await _supabase.rpc('record_investor_capital', params: {
        'p_investor_id': investorId, 
        'p_amount': amount ?? investedAmount ?? 0, 
        'p_notes': notes
      });
    }
  }

  Future<void> payInvestorProfit({
    required String investorId, 
    required double amount, 
    required String bankAccountId,
    required String createdByUid,
    String? notes,
  }) async {
    await _supabase.rpc('pay_investor_profit', params: {
      'p_investor_id': investorId, 
      'p_amount': amount, 
      'p_bank_account_id': bankAccountId,
      'p_created_by_uid': createdByUid,
      'p_notes': notes
    });
    _investorPerformanceCache.remove(investorId);
    notifyListeners();
  }

  Future<void> withdrawInvestorCapital({
    required String investorId, 
    required double amount, 
    required String bankAccountId,
    required String createdByUid,
    String? notes,
  }) async {
    await _supabase.rpc('record_investor_capital', params: {
      'p_investor_id': investorId, 'p_amount': -amount, 'p_notes': notes
    });
  }

  Future<void> recordExpense({
    required String type, 
    required double amount, 
    String? sourceId, 
    String? category,
    String? notes, 
    required String createdByUid,
  }) async {
    await _supabase.rpc('record_expense', params: {
      'p_type': type, 
      'p_amount': amount, 
      'p_target_id': sourceId, 
      'p_category': category,
      'p_notes': notes, 
      'p_created_by_uid': createdByUid
    });
  }

  Future<void> issueLoan({
    required String borrowerName, 
    required String borrowerPhone, 
    required double amount, 
    required LoanSourceType sourceType, 
    required String sourceId, 
    String? notes, 
    required String createdByUid,
  }) async {
    await _supabase.rpc('issue_loan', params: {
      'p_borrower_name': borrowerName, 
      'p_borrower_phone': borrowerPhone, 
      'p_amount': amount, 
      'p_source_type': sourceType.name, 
      'p_source_id': sourceId, 
      'p_notes': notes, 
      'p_created_by_uid': createdByUid
    });
  }

  Future<void> recordLoanRepayment({
    required String loanId, 
    required double amount, 
    required String createdByUid,
  }) async {
    // UI doesn't provide targetType and targetId, so we will use dummy ones for now or fetch the loan locally
    final loan = _loans.firstWhere((l) => l.id == loanId);
    await _supabase.rpc('record_loan_repayment', params: {
      'p_loan_id': loanId, 
      'p_amount': amount, 
      'p_target_type': loan.sourceType.name, 
      'p_target_id': loan.sourceId, 
      'p_notes': null, 
      'p_created_by_uid': createdByUid
    });
  }

  Future<void> ensureCollectorRecord({required String uid, required String name, required String email}) async {
    await _supabase.from('collectors').upsert({'uid': uid, 'name': name, 'email': email});
  }

  Future<void> assignRetailerToCollector(String retailerId, String? collectorUid) async {
    await _supabase.from('retailers').update({'assigned_collector_id': collectorUid}).eq('id', retailerId);
  }

  Future<void> _loadBankAccounts() async {}
  Future<void> _loadLedger() async {}
  Future<void> _loadRetailers() async {}
  Future<void> _loadCollectors() async {}
}
