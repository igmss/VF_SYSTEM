import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/distribution_provider.dart';
import 'retailer_assignment_ussd_runner.dart';
import 'retailer_portal_service.dart';

/// Listens for pending retailer VF assignment requests and processes them one-by-one via USSD when enabled.
class RetailerUssdAutoQueueService extends ChangeNotifier {
  RetailerUssdAutoQueueService();

  static const _kEnabled = 'retailer_auto_ussd_queue_enabled';
  static const _kVfId = 'retailer_auto_ussd_default_vf_id';
  static const _kExternal = 'retailer_auto_ussd_external_wallet';
  static const _kCredit = 'retailer_auto_ussd_apply_credit';

  final RetailerPortalService _portal = RetailerPortalService();

  AuthProvider? _auth;
  AppProvider? _app;
  DistributionProvider? _dist;

  StreamSubscription<List<RetailerPortalRequestRow>>? _sub;
  bool _busy = false;
  bool _prefsLoaded = false;

  /// Latest portal snapshot (for chaining the next job without resubscribing).
  List<RetailerPortalRequestRow> _latestRows = [];

  /// Skip auto-processing this request until [ms] (insufficient balance, etc.) to avoid tight loops.
  final Map<String, int> _skipRequestUntilMs = {};

  /// After finalize fails (e.g. server error) while USSD may have succeeded — never auto-redial this id.
  final Set<String> _blockedAutoRetryIds = {};

  bool _enabled = false;
  String? _defaultVfNumberId;
  bool _defaultExternalWallet = false;
  bool _defaultApplyCredit = false;

  String? _statusLine;
  String? _lastError;

  bool get isAutoQueueEnabled => _enabled;
  String? get defaultVfNumberId => _defaultVfNumberId;
  bool get defaultExternalWallet => _defaultExternalWallet;
  bool get defaultApplyCredit => _defaultApplyCredit;
  bool get isProcessing => _busy;
  String? get statusLine => _statusLine;
  String? get lastError => _lastError;

  Future<void> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    _enabled = p.getBool(_kEnabled) ?? false;
    _defaultVfNumberId = p.getString(_kVfId);
    _defaultExternalWallet = p.getBool(_kExternal) ?? false;
    _defaultApplyCredit = p.getBool(_kCredit) ?? false;
    _prefsLoaded = true;
    notifyListeners();
    _syncSubscription();
  }

  Future<void> setAutoQueueEnabled(bool v) async {
    _enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, v);
    notifyListeners();
    _syncSubscription();
  }

  Future<void> setDefaultVfNumberId(String? id) async {
    _defaultVfNumberId = id;
    final p = await SharedPreferences.getInstance();
    if (id == null || id.isEmpty) {
      await p.remove(_kVfId);
    } else {
      await p.setString(_kVfId, id);
    }
    notifyListeners();
  }

  Future<void> setDefaultExternalWallet(bool v) async {
    _defaultExternalWallet = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kExternal, v);
    notifyListeners();
  }

  Future<void> setDefaultApplyCredit(bool v) async {
    _defaultApplyCredit = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kCredit, v);
    notifyListeners();
  }

  /// Attach Firebase-backed providers (call from Admin dashboard when mounted).
  void attach({
    required AuthProvider auth,
    required AppProvider app,
    required DistributionProvider dist,
  }) {
    _auth = auth;
    _app = app;
    _dist = dist;
    _syncSubscription();
  }

  void detach() {
    _sub?.cancel();
    _sub = null;
    _auth = null;
    _app = null;
    _dist = null;
  }

  bool get _mayRun {
    final a = _auth;
    if (a == null) return false;
    if (!(a.isAdmin || a.isFinance)) return false;
    return _prefsLoaded && _enabled;
  }

  void _syncSubscription() {
    _sub?.cancel();
    _sub = null;
    if (!_mayRun) {
      _statusLine = null;
      notifyListeners();
      return;
    }
    _sub = _portal.streamAllRequests().listen(_onRequests, onError: (Object e, StackTrace st) {
      _lastError = '$e';
      notifyListeners();
      debugPrint('RetailerUssdAutoQueue: stream error $e');
    });
  }

  void _onRequests(List<RetailerPortalRequestRow> rows) {
    _latestRows = rows;
    if (!_mayRun || _busy) return;
    final dist = _dist;
    final app = _app;
    final auth = _auth;
    if (dist == null || app == null || auth == null) return;
    if (dist.isDistributing) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _skipRequestUntilMs.removeWhere((_, until) => until <= nowMs);

    final pending = rows
        .where((r) =>
            r.request.status == 'PENDING' && !_blockedAutoRetryIds.contains(r.request.id))
        .toList()
      ..sort((a, b) => a.request.createdAt.compareTo(b.request.createdAt));
    if (pending.isEmpty) {
      _statusLine = null;
      notifyListeners();
      return;
    }

    final vfId = _defaultVfNumberId;
    if (vfId == null || vfId.isEmpty) {
      _lastError = 'Auto USSD: set a default VF line in Settings.';
      _statusLine = null;
      notifyListeners();
      return;
    }

    final head = pending.first;
    final skipUntil = _skipRequestUntilMs[head.request.id];
    if (skipUntil != null && nowMs < skipUntil) {
      return;
    }

    unawaited(_runHead(head, auth.currentUser?.uid ?? 'system', app, dist));
  }

  Future<void> _runHead(
    RetailerPortalRequestRow row,
    String adminUid,
    AppProvider app,
    DistributionProvider dist,
  ) async {
    if (_busy) return;
    _busy = true;
    _lastError = null;
    _statusLine = '${row.request.id} (${row.request.requestedAmount.toStringAsFixed(0)} EGP)';
    notifyListeners();

    final vfId = _defaultVfNumberId!;
    final amount = row.request.requestedAmount;

    try {
      MobileNumber mobile;
      try {
        mobile = app.mobileNumbers.firstWhere((n) => n.id == vfId);
      } catch (_) {
        _lastError = 'Auto USSD: default VF number no longer exists.';
        return;
      }

      double formFees = 0;
      if (_defaultExternalWallet) {
        formFees = amount * 0.005;
        if (formFees > 15.0) formFees = 15.0;
      }

      if (!RetailerAssignmentUssdRunner.hasLikelySufficientBalance(
        vfNumber: mobile,
        amount: amount,
        isExternalWallet: _defaultExternalWallet,
      )) {
        _lastError =
            'Auto USSD skipped: insufficient balance on ${mobile.phoneNumber} for ${amount.toStringAsFixed(0)} EGP (+fees).';
        _skipRequestUntilMs[row.request.id] =
            DateTime.now().millisecondsSinceEpoch + 90000;
        return;
      }

      final result = await RetailerAssignmentUssdRunner.run(
        row: row,
        adminUid: adminUid,
        selectedNumId: vfId,
        amount: amount,
        formFees: formFees,
        isExternalWallet: _defaultExternalWallet,
        applyCredit: _defaultApplyCredit,
        adminNotes: 'Auto-queue',
        distribution: dist,
        app: app,
        portal: _portal,
      );

      if (!result.success) {
        _lastError = result.message.isEmpty ? 'Auto USSD failed' : result.message;
        if (result.message.startsWith('Finalize failed')) {
          _blockedAutoRetryIds.add(row.request.id);
        }
        if (result.message.contains('timed out')) {
          _skipRequestUntilMs[row.request.id] =
              DateTime.now().millisecondsSinceEpoch + 180000;
        }
      }
    } catch (e, st) {
      _lastError = 'Auto USSD error: $e';
      debugPrint('Auto USSD: $e\n$st');
    } finally {
      _busy = false;
      _statusLine = null;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (_mayRun && !_busy) {
        _onRequests(_latestRows);
      }
    }
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}
